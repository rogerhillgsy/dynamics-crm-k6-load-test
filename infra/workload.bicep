param location string
param registryName string
param containerAppsEnvironmentName string
param jobName string
param imageTag string
param crmBaseUrl string
param crmTenantId string
param crmClientId string
@secure()
param crmClientSecret string
param crmApiVersion string
param lookupField string
param contactEmailDomain string
param contactTelephonePrefix string
param iterations int
param virtualUsers int
param maxDuration string

var acrPullRoleDefinitionId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: registryName
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${containerAppsEnvironmentName}-logs'
  location: location
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource environment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppsEnvironmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

resource pullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${jobName}-pull'
  location: location
}

resource acrPullAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, pullIdentity.id, acrPullRoleDefinitionId)
  scope: registry
  properties: {
    principalId: pullIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleDefinitionId)
  }
}

resource job 'Microsoft.App/jobs@2024-03-01' = {
  name: jobName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${pullIdentity.id}': {}
    }
  }
  properties: {
    environmentId: environment.id
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 7200
      replicaRetryLimit: 0
      manualTriggerConfig: {
        parallelism: 1
        replicaCompletionCount: 1
      }
      registries: [
        {
          server: registry.properties.loginServer
          identity: pullIdentity.id
        }
      ]
      secrets: [
        {
          name: 'crm-client-secret'
          value: crmClientSecret
        }
      ]
    }
    template: {
      containers: [
        {
          name: jobName
          image: '${registry.properties.loginServer}/dynamics-crm-k6:${imageTag}'
          resources: {
            cpu: 1
            memory: '2Gi'
          }
          env: [
            {
              name: 'CRM_BASE_URL'
              value: crmBaseUrl
            }
            {
              name: 'CRM_TENANT_ID'
              value: crmTenantId
            }
            {
              name: 'CRM_CLIENT_ID'
              value: crmClientId
            }
            {
              name: 'CRM_CLIENT_SECRET'
              secretRef: 'crm-client-secret'
            }
            {
              name: 'CRM_API_VERSION'
              value: crmApiVersion
            }
            {
              name: 'LOOKUP_FIELD'
              value: lookupField
            }
            {
              name: 'CONTACT_EMAIL_DOMAIN'
              value: contactEmailDomain
            }
            {
              name: 'CONTACT_TELEPHONE_PREFIX'
              value: contactTelephonePrefix
            }
            {
              name: 'ITERATIONS'
              value: string(iterations)
            }
            {
              name: 'VUS'
              value: string(virtualUsers)
            }
            {
              name: 'MAX_DURATION'
              value: maxDuration
            }
          ]
        }
      ]
    }
  }
  dependsOn: [
    acrPullAssignment
  ]
}

output registryLoginServer string = registry.properties.loginServer
output jobName string = job.name
