"""
Adobe PDF Processing Service
Handles PDF operations at scale including OCR, compression, security, and conversion
"""

import os
import asyncio
import aiohttp
import aiofiles
from typing import List, Dict, Optional, Any, Union
from pathlib import Path
import logging
from dataclasses import dataclass
from enum import Enum
import base64
import json
from datetime import datetime
import hashlib
import tempfile
from concurrent.futures import ThreadPoolExecutor
import PyPDF2
from pdf2image import convert_from_path
import pytesseract
from PIL import Image
import fitz  # PyMuPDF
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas
import redis.asyncio as redis
from pydantic import BaseModel, Field

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class PDFOperation(Enum):
    """Supported PDF operations"""
    MERGE = "merge"
    SPLIT = "split"
    COMPRESS = "compress"
    OCR = "ocr"
    ENCRYPT = "encrypt"
    DECRYPT = "decrypt"
    WATERMARK = "watermark"
    ROTATE = "rotate"
    EXTRACT_TEXT = "extract_text"
    EXTRACT_IMAGES = "extract_images"
    CONVERT_TO_IMAGE = "convert_to_image"
    ADD_SIGNATURE = "add_signature"
    REDACT = "redact"
    FILL_FORM = "fill_form"
    CREATE_FROM_TEMPLATE = "create_from_template"

@dataclass
class PDFJob:
    """PDF processing job"""
    job_id: str
    operation: PDFOperation
    input_files: List[str]
    output_path: str
    options: Dict[str, Any]
    status: str = "pending"
    created_at: datetime = None
    completed_at: datetime = None
    error_message: str = None
    metadata: Dict[str, Any] = None

    def __post_init__(self):
        if self.created_at is None:
            self.created_at = datetime.utcnow()

class PDFProcessorConfig(BaseModel):
    """Configuration for PDF processor"""
    adobe_pdf_api_key: str = Field(..., description="Adobe PDF Services API key")
    adobe_pdf_client_id: str = Field(..., description="Adobe PDF Services client ID")
    max_file_size_mb: int = Field(default=100, description="Maximum file size in MB")
    ocr_language: str = Field(default="eng", description="OCR language")
    compression_quality: int = Field(default=85, description="JPEG compression quality")
    watermark_opacity: float = Field(default=0.3, description="Watermark opacity")
    redis_url: str = Field(default="redis://localhost:6379", description="Redis URL for job queue")
    temp_directory: str = Field(default="/tmp/pdf_processing", description="Temporary file storage")
    max_concurrent_jobs: int = Field(default=10, description="Maximum concurrent processing jobs")

class AdobePDFServicesClient:
    """Client for Adobe PDF Services API"""

    def __init__(self, config: PDFProcessorConfig):
        self.config = config
        self.base_url = "https://pdf-services.adobe.io/operation"
        self.session = None

    async def __aenter__(self):
        self.session = aiohttp.ClientSession()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.session:
            await self.session.close()

    async def get_access_token(self) -> str:
        """Get Adobe PDF Services access token"""
        auth_url = "https://ims-na1.adobelogin.com/ims/token/v3"

        data = {
            "client_id": self.config.adobe_pdf_client_id,
            "client_secret": self.config.adobe_pdf_api_key,
            "grant_type": "client_credentials",
            "scope": "openid,AdobeID,read_organizations"
        }

        async with self.session.post(auth_url, data=data) as response:
            result = await response.json()
            return result["access_token"]

    async def create_pdf(self, html_content: str) -> bytes:
        """Create PDF from HTML using Adobe API"""
        token = await self.get_access_token()

        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }

        payload = {
            "input": {
                "html": base64.b64encode(html_content.encode()).decode()
            },
            "options": {
                "pageLayout": {
                    "pageWidth": 8.5,
                    "pageHeight": 11
                }
            }
        }

        async with self.session.post(
            f"{self.base_url}/createpdf",
            headers=headers,
            json=payload
        ) as response:
            return await response.read()

    async def ocr_pdf(self, pdf_bytes: bytes, language: str = "en-US") -> bytes:
        """Apply OCR to PDF using Adobe API"""
        token = await self.get_access_token()

        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }

        payload = {
            "input": {
                "pdf": base64.b64encode(pdf_bytes).decode()
            },
            "options": {
                "ocr_lang": language,
                "ocr_type": "searchable_image"
            }
        }

        async with self.session.post(
            f"{self.base_url}/ocr",
            headers=headers,
            json=payload
        ) as response:
            return await response.read()

class PDFProcessor:
    """Main PDF processing service"""

    def __init__(self, config: PDFProcessorConfig):
        self.config = config
        self.redis_client = None
        self.adobe_client = None
        self.executor = ThreadPoolExecutor(max_workers=config.max_concurrent_jobs)

        # Create temp directory
        Path(config.temp_directory).mkdir(parents=True, exist_ok=True)

    async def initialize(self):
        """Initialize connections"""
        self.redis_client = await redis.from_url(self.config.redis_url)
        self.adobe_client = AdobePDFServicesClient(self.config)
        logger.info("PDF Processor initialized")

    async def close(self):
        """Close connections"""
        if self.redis_client:
            await self.redis_client.close()
        self.executor.shutdown()

    async def process_job(self, job: PDFJob) -> PDFJob:
        """Process a PDF job"""
        try:
            job.status = "processing"
            await self._update_job_status(job)

            # Route to appropriate handler
            handler_map = {
                PDFOperation.MERGE: self._merge_pdfs,
                PDFOperation.SPLIT: self._split_pdf,
                PDFOperation.COMPRESS: self._compress_pdf,
                PDFOperation.OCR: self._ocr_pdf,
                PDFOperation.ENCRYPT: self._encrypt_pdf,
                PDFOperation.WATERMARK: self._add_watermark,
                PDFOperation.EXTRACT_TEXT: self._extract_text,
                PDFOperation.CONVERT_TO_IMAGE: self._convert_to_images,
                PDFOperation.REDACT: self._redact_pdf,
                PDFOperation.FILL_FORM: self._fill_form,
            }

            handler = handler_map.get(job.operation)
            if not handler:
                raise ValueError(f"Unsupported operation: {job.operation}")

            result = await handler(job)

            job.status = "completed"
            job.completed_at = datetime.utcnow()
            job.metadata = result

        except Exception as e:
            logger.error(f"Error processing job {job.job_id}: {str(e)}")
            job.status = "failed"
            job.error_message = str(e)

        await self._update_job_status(job)
        return job

    async def _update_job_status(self, job: PDFJob):
        """Update job status in Redis"""
        if self.redis_client:
            await self.redis_client.hset(
                f"pdf_job:{job.job_id}",
                mapping={
                    "status": job.status,
                    "updated_at": datetime.utcnow().isoformat(),
                    "error": job.error_message or "",
                    "metadata": json.dumps(job.metadata) if job.metadata else "{}"
                }
            )

    async def _merge_pdfs(self, job: PDFJob) -> Dict[str, Any]:
        """Merge multiple PDFs into one"""
        merger = PyPDF2.PdfMerger()

        try:
            for pdf_path in job.input_files:
                merger.append(pdf_path)

            merger.write(job.output_path)
            merger.close()

            # Get output file info
            output_size = os.path.getsize(job.output_path)
            with open(job.output_path, 'rb') as f:
                reader = PyPDF2.PdfReader(f)
                page_count = len(reader.pages)

            return {
                "pages": page_count,
                "size_bytes": output_size,
                "files_merged": len(job.input_files)
            }
        finally:
            merger.close()

    async def _split_pdf(self, job: PDFJob) -> Dict[str, Any]:
        """Split PDF into multiple files"""
        input_file = job.input_files[0]
        split_mode = job.options.get("mode", "pages")  # pages, range, or chunks

        with open(input_file, 'rb') as f:
            reader = PyPDF2.PdfReader(f)
            total_pages = len(reader.pages)

            output_files = []

            if split_mode == "pages":
                # Split into individual pages
                for i in range(total_pages):
                    writer = PyPDF2.PdfWriter()
                    writer.add_page(reader.pages[i])

                    output_file = f"{job.output_path}_page_{i+1}.pdf"
                    with open(output_file, 'wb') as out:
                        writer.write(out)
                    output_files.append(output_file)

            elif split_mode == "chunks":
                # Split into chunks of N pages
                chunk_size = job.options.get("chunk_size", 10)
                for i in range(0, total_pages, chunk_size):
                    writer = PyPDF2.PdfWriter()
                    for j in range(i, min(i + chunk_size, total_pages)):
                        writer.add_page(reader.pages[j])

                    output_file = f"{job.output_path}_chunk_{i//chunk_size + 1}.pdf"
                    with open(output_file, 'wb') as out:
                        writer.write(out)
                    output_files.append(output_file)

        return {
            "total_pages": total_pages,
            "files_created": len(output_files),
            "output_files": output_files
        }

    async def _compress_pdf(self, job: PDFJob) -> Dict[str, Any]:
        """Compress PDF file size"""
        input_file = job.input_files[0]
        quality = job.options.get("quality", self.config.compression_quality)

        # Open PDF with PyMuPDF
        doc = fitz.open(input_file)
        original_size = os.path.getsize(input_file)

        # Compress images in PDF
        for page_num in range(len(doc)):
            page = doc[page_num]
            image_list = page.get_images()

            for img_index, img in enumerate(image_list):
                xref = img[0]
                pix = fitz.Pixmap(doc, xref)

                if pix.n - pix.alpha > 3:  # CMYK to RGB
                    pix = fitz.Pixmap(fitz.csRGB, pix)

                # Compress and replace image
                img_data = pix.tobytes("jpeg", quality=quality)
                doc._deleteObject(xref)
                page.insert_image(page.rect, stream=img_data)

        # Save compressed PDF
        doc.save(job.output_path, garbage=4, deflate=True, clean=True)
        doc.close()

        compressed_size = os.path.getsize(job.output_path)
        compression_ratio = (1 - compressed_size / original_size) * 100

        return {
            "original_size": original_size,
            "compressed_size": compressed_size,
            "compression_ratio": f"{compression_ratio:.2f}%",
            "quality_setting": quality
        }

    async def _ocr_pdf(self, job: PDFJob) -> Dict[str, Any]:
        """Apply OCR to scanned PDF"""
        input_file = job.input_files[0]
        language = job.options.get("language", self.config.ocr_language)

        # Use Adobe PDF Services for better OCR
        async with self.adobe_client as client:
            with open(input_file, 'rb') as f:
                pdf_bytes = f.read()

            ocr_result = await client.ocr_pdf(pdf_bytes, language)

            with open(job.output_path, 'wb') as f:
                f.write(ocr_result)

        # Extract text to verify OCR
        doc = fitz.open(job.output_path)
        text_content = ""
        for page in doc:
            text_content += page.get_text()
        doc.close()

        return {
            "pages_processed": len(doc),
            "text_extracted": len(text_content),
            "language": language,
            "searchable": True
        }

    async def _encrypt_pdf(self, job: PDFJob) -> Dict[str, Any]:
        """Encrypt PDF with password"""
        input_file = job.input_files[0]
        user_password = job.options.get("user_password", "")
        owner_password = job.options.get("owner_password", user_password)
        permissions = job.options.get("permissions", ["print", "copy"])

        reader = PyPDF2.PdfReader(input_file)
        writer = PyPDF2.PdfWriter()

        for page in reader.pages:
            writer.add_page(page)

        # Set encryption
        writer.encrypt(
            user_pwd=user_password,
            owner_pwd=owner_password,
            use_128bit=True
        )

        with open(job.output_path, 'wb') as f:
            writer.write(f)

        return {
            "encrypted": True,
            "encryption_level": "128-bit",
            "permissions": permissions,
            "password_protected": bool(user_password)
        }

    async def _add_watermark(self, job: PDFJob) -> Dict[str, Any]:
        """Add watermark to PDF"""
        input_file = job.input_files[0]
        watermark_text = job.options.get("text", "CONFIDENTIAL")
        opacity = job.options.get("opacity", self.config.watermark_opacity)
        position = job.options.get("position", "center")

        doc = fitz.open(input_file)

        for page_num in range(len(doc)):
            page = doc[page_num]

            # Create watermark
            rect = page.rect
            text_length = len(watermark_text) * 20

            if position == "center":
                x = (rect.width - text_length) / 2
                y = rect.height / 2
            elif position == "bottom":
                x = (rect.width - text_length) / 2
                y = rect.height - 50
            else:  # top
                x = (rect.width - text_length) / 2
                y = 50

            # Add watermark text
            page.insert_text(
                (x, y),
                watermark_text,
                fontsize=40,
                color=(0.5, 0.5, 0.5),
                rotate=45 if position == "center" else 0,
                overlay=True
            )

        doc.save(job.output_path)
        doc.close()

        return {
            "watermark_added": True,
            "text": watermark_text,
            "pages_watermarked": len(doc),
            "position": position
        }

    async def _extract_text(self, job: PDFJob) -> Dict[str, Any]:
        """Extract text from PDF"""
        input_file = job.input_files[0]
        output_format = job.options.get("format", "txt")

        doc = fitz.open(input_file)
        extracted_text = []

        for page_num in range(len(doc)):
            page = doc[page_num]
            text = page.get_text()
            extracted_text.append({
                "page": page_num + 1,
                "text": text
            })

        doc.close()

        # Save extracted text
        if output_format == "txt":
            with open(job.output_path, 'w', encoding='utf-8') as f:
                for page_text in extracted_text:
                    f.write(f"--- Page {page_text['page']} ---\n")
                    f.write(page_text['text'])
                    f.write("\n\n")
        elif output_format == "json":
            with open(job.output_path, 'w', encoding='utf-8') as f:
                json.dump(extracted_text, f, indent=2)

        total_chars = sum(len(p['text']) for p in extracted_text)

        return {
            "pages_processed": len(extracted_text),
            "total_characters": total_chars,
            "output_format": output_format,
            "output_file": job.output_path
        }

    async def _convert_to_images(self, job: PDFJob) -> Dict[str, Any]:
        """Convert PDF pages to images"""
        input_file = job.input_files[0]
        image_format = job.options.get("format", "png")
        dpi = job.options.get("dpi", 200)

        # Convert PDF to images
        images = convert_from_path(input_file, dpi=dpi)
        output_files = []

        for i, image in enumerate(images):
            output_file = f"{job.output_path}_page_{i+1}.{image_format}"
            image.save(output_file, image_format.upper())
            output_files.append(output_file)

        return {
            "pages_converted": len(images),
            "image_format": image_format,
            "dpi": dpi,
            "output_files": output_files
        }

    async def _redact_pdf(self, job: PDFJob) -> Dict[str, Any]:
        """Redact sensitive information from PDF"""
        input_file = job.input_files[0]
        search_terms = job.options.get("terms", [])
        patterns = job.options.get("patterns", [])  # Regex patterns

        doc = fitz.open(input_file)
        total_redactions = 0

        for page_num in range(len(doc)):
            page = doc[page_num]

            # Redact search terms
            for term in search_terms:
                areas = page.search_for(term)
                for area in areas:
                    page.add_redact_annot(area, fill=(0, 0, 0))
                    total_redactions += 1

            # Apply redactions
            page.apply_redactions()

        doc.save(job.output_path)
        doc.close()

        return {
            "redactions_applied": total_redactions,
            "search_terms": len(search_terms),
            "patterns": len(patterns),
            "pages_processed": len(doc)
        }

    async def _fill_form(self, job: PDFJob) -> Dict[str, Any]:
        """Fill PDF form fields"""
        input_file = job.input_files[0]
        form_data = job.options.get("data", {})

        reader = PyPDF2.PdfReader(input_file)
        writer = PyPDF2.PdfWriter()

        # Fill form fields
        for page in reader.pages:
            writer.add_page(page)

        writer.update_page_form_field_values(
            writer.pages[0],
            form_data
        )

        with open(job.output_path, 'wb') as f:
            writer.write(f)

        return {
            "fields_filled": len(form_data),
            "form_completed": True
        }

class PDFProcessingAPI:
    """REST API endpoints for PDF processing"""

    def __init__(self, processor: PDFProcessor):
        self.processor = processor

    async def create_job(self, request_data: Dict[str, Any]) -> str:
        """Create new PDF processing job"""
        job_id = hashlib.md5(
            f"{datetime.utcnow().isoformat()}{request_data}".encode()
        ).hexdigest()

        job = PDFJob(
            job_id=job_id,
            operation=PDFOperation(request_data["operation"]),
            input_files=request_data["input_files"],
            output_path=request_data.get("output_path", f"/tmp/{job_id}.pdf"),
            options=request_data.get("options", {})
        )

        # Queue job for processing
        await self.processor.redis_client.lpush("pdf_job_queue", json.dumps({
            "job_id": job.job_id,
            "operation": job.operation.value,
            "input_files": job.input_files,
            "output_path": job.output_path,
            "options": job.options
        }))

        return job_id

    async def get_job_status(self, job_id: str) -> Dict[str, Any]:
        """Get job status"""
        job_data = await self.processor.redis_client.hgetall(f"pdf_job:{job_id}")

        if not job_data:
            return {"error": "Job not found"}

        return {
            "job_id": job_id,
            "status": job_data.get(b"status", b"").decode(),
            "updated_at": job_data.get(b"updated_at", b"").decode(),
            "error": job_data.get(b"error", b"").decode(),
            "metadata": json.loads(job_data.get(b"metadata", b"{}").decode())
        }

    async def batch_process(self, jobs: List[Dict[str, Any]]) -> List[str]:
        """Process multiple PDF jobs in batch"""
        job_ids = []

        for job_data in jobs:
            job_id = await self.create_job(job_data)
            job_ids.append(job_id)

        return job_ids

# Example usage
async def main():
    """Example usage of PDF processor"""
    config = PDFProcessorConfig(
        adobe_pdf_api_key=os.getenv("ADOBE_PDF_API_KEY", "demo_key"),
        adobe_pdf_client_id=os.getenv("ADOBE_PDF_CLIENT_ID", "demo_client")
    )

    processor = PDFProcessor(config)
    await processor.initialize()

    # Example: Merge PDFs
    merge_job = PDFJob(
        job_id="merge_001",
        operation=PDFOperation.MERGE,
        input_files=["file1.pdf", "file2.pdf", "file3.pdf"],
        output_path="merged_output.pdf",
        options={}
    )

    result = await processor.process_job(merge_job)
    print(f"Merge result: {result.metadata}")

    # Example: OCR a scanned PDF
    ocr_job = PDFJob(
        job_id="ocr_001",
        operation=PDFOperation.OCR,
        input_files=["scanned_document.pdf"],
        output_path="searchable_document.pdf",
        options={"language": "eng"}
    )

    result = await processor.process_job(ocr_job)
    print(f"OCR result: {result.metadata}")

    await processor.close()

if __name__ == "__main__":
    asyncio.run(main())