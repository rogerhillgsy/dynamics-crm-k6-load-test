targetScope = 'subscription'

param location string
param resourceGroupName string
param registryName string

resource registryResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
}

module registry './registry.bicep' = {
  name: 'dynamicsCrmK6Registry'
  scope: registryResourceGroup
  params: {
    location: location
    registryName: registryName
  }
}

output loginServer string = registry.outputs.loginServer
