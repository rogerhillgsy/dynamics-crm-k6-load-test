targetScope = 'subscription'

@description('Azure region for all deployed resources.')
param location string

@description('Resource group that contains the load-test resources.')
param resourceGroupName string

@description('Globally unique Azure Container Registry name.')
param registryName string

@description('Azure Container Apps Environment name.')
param containerAppsEnvironmentName string

@description('Azure Container Apps Job name.')
param jobName string

@description('Image tag to deploy from the Azure Container Registry.')
param imageTag string

@description('Dynamics 365 environment URL, for example https://example.crm.dynamics.com.')
param crmBaseUrl string

@description('Microsoft Entra tenant ID used for client-credentials authentication.')
param crmTenantId string

@description('Application (client) ID of the Dynamics CRM application user.')
param crmClientId string

@secure()
@description('Client secret for the Dynamics CRM application user.')
param crmClientSecret string

@description('Dynamics Web API version.')
param crmApiVersion string = 'v9.2'

@description('Lookup contacts by email or telephone.')
@allowed([
  'email'
  'telephone'
])
param lookupField string = 'email'

@description('Email domain for synthetic test contacts.')
param contactEmailDomain string = 'loadtest.example.invalid'

@description('Prefix used to create synthetic phone numbers. Required for telephone lookups.')
param contactTelephonePrefix string = ''

@description('Number of complete contact and phone-call test iterations.')
param iterations int = 1

@description('Number of k6 virtual users.')
param virtualUsers int = 1

@description('Maximum duration allowed for the k6 shared-iterations scenario.')
param maxDuration string = '10m'

resource workloadResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
}

module workload './workload.bicep' = {
  name: 'dynamicsCrmK6Workload'
  scope: workloadResourceGroup
  params: {
    location: location
    registryName: registryName
    containerAppsEnvironmentName: containerAppsEnvironmentName
    jobName: jobName
    imageTag: imageTag
    crmBaseUrl: crmBaseUrl
    crmTenantId: crmTenantId
    crmClientId: crmClientId
    crmClientSecret: crmClientSecret
    crmApiVersion: crmApiVersion
    lookupField: lookupField
    contactEmailDomain: contactEmailDomain
    contactTelephonePrefix: contactTelephonePrefix
    iterations: iterations
    virtualUsers: virtualUsers
    maxDuration: maxDuration
  }
}
