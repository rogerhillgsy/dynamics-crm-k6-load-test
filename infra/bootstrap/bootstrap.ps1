$location = "uksounth"
$resourceGroup = "rg-dynamics-crm-k6"
$registry = "rbhconsultingacr"
$environment = "cae-dynamics-crm-k6"
$job = "job-dynamics-crm-k6"
$imageTag = "latest"
$crmUrl = "https://rbhcuk.crm11.dynamics.com"
$tenantId = "0699e5de-8e14-4867-bd8f-fef147a2b3e2"
$clientId = "e8c1ab45-d373-48bf-98b0-fa9a82008151"
$clientSecret = Read-Host "Dynamics application client secret" -AsSecureString
$clientSecretText = [System.Net.NetworkCredential]::new("", $clientSecret).Password

##

az acr login --name $registry
docker build --tag "${registry}.azurecr.io/dynamics-crm-k6:${imageTag}" .
docker push "${registry}.azurecr.io/dynamics-crm-k6:${imageTag}"