# Variables for Adobe Enterprise Automation Infrastructure

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "adobe-automation"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "adobe-automation-rg"
}

variable "owner" {
  description = "Owner of the resources"
  type        = string
  default     = "IT Operations"
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = "IT-001"
}

# AKS Configuration
variable "kubernetes_version" {
  description = "Kubernetes version for AKS"
  type        = string
  default     = "1.27.7"
}

variable "node_count" {
  description = "Initial number of nodes"
  type        = number
  default     = 3
}

variable "min_node_count" {
  description = "Minimum number of nodes for autoscaling"
  type        = number
  default     = 2
}

variable "max_node_count" {
  description = "Maximum number of nodes for autoscaling"
  type        = number
  default     = 10
}

variable "node_size" {
  description = "Size of the AKS nodes"
  type        = string
  default     = "Standard_D2_v3"
}

# SQL Configuration
variable "sql_admin_username" {
  description = "Admin username for SQL Server"
  type        = string
  default     = "sqladmin"
  sensitive   = true
}

# Adobe API Configuration
variable "adobe_client_id" {
  description = "Adobe API Client ID"
  type        = string
  sensitive   = true
}

variable "adobe_client_secret" {
  description = "Adobe API Client Secret"
  type        = string
  sensitive   = true
}

variable "adobe_org_id" {
  description = "Adobe Organization ID"
  type        = string
  sensitive   = true
}

variable "adobe_api_key" {
  description = "Adobe API Key"
  type        = string
  sensitive   = true
}

# Application Configuration
variable "jwt_secret" {
  description = "JWT secret for API authentication"
  type        = string
  default     = ""
  sensitive   = true
}

variable "api_replicas" {
  description = "Number of API server replicas"
  type        = number
  default     = 3
}

variable "enable_monitoring" {
  description = "Enable Application Insights monitoring"
  type        = bool
  default     = true
}

variable "enable_backups" {
  description = "Enable automated backups"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
}

# Network Configuration
variable "allowed_ip_ranges" {
  description = "IP ranges allowed to access the resources"
  type        = list(string)
  default     = []
}

variable "enable_private_endpoints" {
  description = "Enable private endpoints for resources"
  type        = bool
  default     = false
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}