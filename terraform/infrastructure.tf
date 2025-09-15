# Terraform Infrastructure as Code for Adobe Automation
# Azure Provider Configuration

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }
  backend "azurerm" {
    resource_group_name  = "adobe-automation-tfstate"
    storage_account_name = "adobeautomationtfstate"
    container_name       = "tfstate"
    key                  = "prod.terraform.tfstate"
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}

# Variables
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "East US"
}

variable "admin_email" {
  description = "Administrator email"
  type        = string
}

# Resource Group
resource "azurerm_resource_group" "adobe_automation" {
  name     = "rg-adobe-automation-${var.environment}"
  location = var.location
  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Application = "Adobe-Automation"
  }
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "vnet-adobe-${var.environment}"
  location            = azurerm_resource_group.adobe_automation.location
  resource_group_name = azurerm_resource_group.adobe_automation.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.adobe_automation.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "database" {
  name                 = "snet-database"
  resource_group_name  = azurerm_resource_group.adobe_automation.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
  service_endpoints    = ["Microsoft.Sql"]
}

# Azure Kubernetes Service
resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-adobe-${var.environment}"
  location            = azurerm_resource_group.adobe_automation.location
  resource_group_name = azurerm_resource_group.adobe_automation.name
  dns_prefix          = "adobe-${var.environment}"

  default_node_pool {
    name                = "default"
    node_count          = 3
    vm_size             = "Standard_D2_v3"
    vnet_subnet_id      = azurerm_subnet.aks.id
    enable_auto_scaling = true
    min_count           = 3
    max_count           = 10
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
  }

  addon_profile {
    oms_agent {
      enabled                    = true
      log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
    }
  }
}

# SQL Database
resource "azurerm_mssql_server" "main" {
  name                         = "sql-adobe-${var.environment}"
  resource_group_name          = azurerm_resource_group.adobe_automation.name
  location                     = azurerm_resource_group.adobe_automation.location
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = random_password.sql_admin.result

  azuread_administrator {
    login_username = "AzureAD Admin"
    object_id      = data.azuread_client_config.current.object_id
  }
}

resource "azurerm_mssql_database" "adobe_automation" {
  name           = "AdobeAutomation"
  server_id      = azurerm_mssql_server.main.id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  max_size_gb    = 100
  sku_name       = "S3"
  zone_redundant = true

  threat_detection_policy {
    state                      = "Enabled"
    email_addresses            = [var.admin_email]
    retention_days             = 30
  }
}

resource "azurerm_mssql_virtual_network_rule" "database" {
  name      = "sql-vnet-rule"
  server_id = azurerm_mssql_server.main.id
  subnet_id = azurerm_subnet.database.id
}

# Redis Cache
resource "azurerm_redis_cache" "main" {
  name                = "redis-adobe-${var.environment}"
  location            = azurerm_resource_group.adobe_automation.location
  resource_group_name = azurerm_resource_group.adobe_automation.name
  capacity            = 2
  family              = "C"
  sku_name            = "Standard"
  enable_non_ssl_port = false

  redis_configuration {
    enable_authentication = true
    maxmemory_policy      = "allkeys-lru"
  }
}

# Key Vault
resource "azurerm_key_vault" "main" {
  name                        = "kv-adobe-${var.environment}"
  location                    = azurerm_resource_group.adobe_automation.location
  resource_group_name         = azurerm_resource_group.adobe_automation.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = true
  sku_name                    = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    certificate_permissions = ["Get", "List", "Create", "Import", "Delete"]
    key_permissions         = ["Get", "List", "Create", "Import", "Delete", "Encrypt", "Decrypt"]
    secret_permissions      = ["Get", "List", "Set", "Delete"]
  }
}

# Store secrets in Key Vault
resource "azurerm_key_vault_secret" "adobe_client_id" {
  name         = "adobe-client-id"
  value        = var.adobe_client_id
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "adobe_client_secret" {
  name         = "adobe-client-secret"
  value        = var.adobe_client_secret
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "sql_connection_string" {
  name         = "sql-connection-string"
  value        = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.adobe_automation.name};Persist Security Info=False;User ID=${azurerm_mssql_server.main.administrator_login};Password=${random_password.sql_admin.result};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  key_vault_id = azurerm_key_vault.main.id
}

# Storage Account for Backups
resource "azurerm_storage_account" "backups" {
  name                     = "stadobebackup${var.environment}"
  resource_group_name      = azurerm_resource_group.adobe_automation.name
  location                 = azurerm_resource_group.adobe_automation.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
  enable_https_traffic_only = true

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 30
    }
  }
}

resource "azurerm_storage_container" "backups" {
  name                  = "backups"
  storage_account_name  = azurerm_storage_account.backups.name
  container_access_type = "private"
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-adobe-${var.environment}"
  location            = azurerm_resource_group.adobe_automation.location
  resource_group_name = azurerm_resource_group.adobe_automation.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# Application Insights
resource "azurerm_application_insights" "main" {
  name                = "appi-adobe-${var.environment}"
  location            = azurerm_resource_group.adobe_automation.location
  resource_group_name = azurerm_resource_group.adobe_automation.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
}

# Container Registry
resource "azurerm_container_registry" "main" {
  name                = "cradobeauto${var.environment}"
  resource_group_name = azurerm_resource_group.adobe_automation.name
  location            = azurerm_resource_group.adobe_automation.location
  sku                 = "Premium"
  admin_enabled       = false

  georeplications {
    location                = "West US"
    zone_redundancy_enabled = true
  }
}

# Random password for SQL admin
resource "random_password" "sql_admin" {
  length  = 32
  special = true
}

# Outputs
output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "sql_server_fqdn" {
  value = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "redis_hostname" {
  value = azurerm_redis_cache.main.hostname
}

output "key_vault_uri" {
  value = azurerm_key_vault.main.vault_uri
}

output "container_registry_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "application_insights_instrumentation_key" {
  value     = azurerm_application_insights.main.instrumentation_key
  sensitive = true
}