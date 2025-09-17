# Outputs for Adobe Enterprise Automation Infrastructure

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name
}

output "aks_cluster_endpoint" {
  description = "Endpoint for the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "aks_kube_config" {
  description = "Kubernetes config for kubectl"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "acr_login_server" {
  description = "Login server for Azure Container Registry"
  value       = azurerm_container_registry.main.login_server
}

output "acr_admin_username" {
  description = "Admin username for ACR"
  value       = azurerm_container_registry.main.admin_username
  sensitive   = true
}

output "acr_admin_password" {
  description = "Admin password for ACR"
  value       = azurerm_container_registry.main.admin_password
  sensitive   = true
}

output "sql_server_fqdn" {
  description = "FQDN of the SQL Server"
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "sql_database_name" {
  description = "Name of the SQL database"
  value       = azurerm_mssql_database.main.name
}

output "redis_hostname" {
  description = "Hostname of Redis Cache"
  value       = azurerm_redis_cache.main.hostname
}

output "redis_port" {
  description = "Port of Redis Cache"
  value       = azurerm_redis_cache.main.ssl_port
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_primary_endpoint" {
  description = "Primary blob endpoint for storage"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "application_insights_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application ID for Application Insights"
  value       = azurerm_application_insights.main.app_id
}

output "connection_strings" {
  description = "Connection strings stored in Key Vault"
  value = {
    sql_connection     = azurerm_key_vault_secret.sql_connection.name
    redis_connection   = azurerm_key_vault_secret.redis_connection.name
    storage_connection = azurerm_key_vault_secret.storage_connection.name
    insights_key       = azurerm_key_vault_secret.insights_key.name
  }
}

output "deployment_info" {
  description = "Deployment information"
  value = {
    environment    = var.environment
    location       = var.location
    project        = var.project_name
    deployed_at    = timestamp()
  }
}