param domain string = ''
param deployedTag string = 'latest'
param name string
param dbName string
param dbPassword string
param location string = resourceGroup().location

var addressPrefix = '10.0.0.0/16'
var vnetName = '${name}-vnet-${uniqueString(resourceGroup().name)}'

resource vnet 'Microsoft.Network/virtualNetworks@2021-02-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    enableVmProtection: false
    enableDdosProtection: false
  }
}

resource webAppSubnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' = {
  parent: vnet
  name: 'WebApp'
  properties: {
    addressPrefix: '10.0.1.0/24'
    delegations: [
      {
        name: 'delegation'
        properties: {
          serviceName: 'Microsoft.Web/serverFarms'
        }
      }
    ]
  }
}

resource dbSubnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' = {
  parent: vnet
  name: 'db'
  properties: {
    addressPrefix: '10.0.2.0/27'
    delegations: [
      {
        name: 'delegation'
        properties: {
          serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
        }
      }
    ]
  }
}

var containerRegistryName = '${replace(name, '-', '')}'
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2020-11-01-preview' = {
  location: location
  name: containerRegistryName
  properties: {
    adminUserEnabled: true
    anonymousPullEnabled: false
    dataEndpointEnabled: false
    encryption: {
      status: 'disabled'
    }
    networkRuleBypassOptions: 'AzureServices'
    policies: {
      quarantinePolicy: {
        status: 'disabled'
      }
      retentionPolicy: {
        days: 7
        status: 'disabled'
      }
      trustPolicy: {
        status: 'disabled'
        type: 'Notary'
      }
    }
    publicNetworkAccess: 'Enabled'
    zoneRedundancy: 'Disabled'
  }
  sku: {
    name: 'Basic'
  }
}

var logAnalyticsWorkspaceName = '${name}-logs-workspace'
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/Workspaces@2020-10-01' = {
  location: location
  name: logAnalyticsWorkspaceName
  properties: {
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    retentionInDays: 30
  }
}

var storageAccountName = '${replace(name, '-', '')}storage'
resource storageAccount 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  kind: 'StorageV2'
  location: location
  name: storageAccountName
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: true
    allowSharedKeyAccess: true
    encryption: {
      keySource: 'Microsoft.Storage'
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
      }
    }
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
    supportsHttpsTrafficOnly: true
  }
  sku: {
    name: 'Standard_RAGRS'
  }
}
resource storageAccountBlob 'Microsoft.Storage/storageAccounts/blobServices@2021-04-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    changeFeed: {
      enabled: false
    }
    containerDeleteRetentionPolicy: {
      days: 7
      enabled: true
    }
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      days: 7
      enabled: true
    }
    isVersioningEnabled: false
    restorePolicy: {
      enabled: false
    }
  }
}

resource assetsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-04-01' = {
  parent: storageAccountBlob
  name: 'assets'
  properties: {
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'Blob'
  }
  dependsOn: [
    storageAccount
  ]
}

resource filesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-04-01' = {
  parent: storageAccountBlob
  name: 'files'
  properties: {
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'Blob'
  }
  dependsOn: [
    storageAccount
  ]
}

resource db 'Microsoft.DBForPostgreSql/flexibleServers@2020-02-14-preview' = {
  location: location
  name: '${name}-db'
  properties: {
    delegatedSubnetArguments: {
      subnetArmResourceId: dbSubnet.id
    }
    administratorLogin: '${replace(name, '-', '_')}_admin'
    administratorLoginPassword: dbPassword
    haEnabled: 'Disabled'
    storageProfile: {
      backupRetentionDays: 7
      storageMB: 32768
    }
    version: '12'
  }
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  dependsOn: [
    dbSubnet
  ]
}

resource default_db 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2020-11-05-preview' = {
  parent: db
  name: 'postgres'
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

resource app_db 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2020-11-05-preview' = {
  parent: db
  name: dbName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

resource allow_all_azure_to_db 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2020-02-14-preview' = {
  parent: db
  name: 'AllowAllAzureServicesAndResourcesWithinAzureIps_2021-6-22_12-54-15'
  properties: {
    endIpAddress: '0.0.0.0'
    startIpAddress: '0.0.0.0'
  }
}

var appServicePlanName = '${name}-asp'
resource appServicePlan 'Microsoft.Web/serverfarms@2020-06-01' = {
  kind: 'linux'
  location: location
  name: appServicePlanName
  properties: {
    hyperV: false
    isSpot: false
    isXenon: false
    maximumElasticWorkerCount: 1
    perSiteScaling: false
    reserved: true
    targetWorkerCount: 0
    targetWorkerSizeId: 0
  }
  sku: {
    capacity: 1
    family: 'S'
    name: 'S1'
    size: 'S1'
    tier: 'Standard'
  }
}

var webAppName = '${name}-webapp'
var dockerImageName = '${containerRegistryName}.azurecr.io/${name}:${deployedTag}'
resource webApp 'Microsoft.Web/sites@2020-06-01' = {
  location: location
  name: webAppName
  identity: {}
  properties: {
    serverFarmId: appServicePlan.id

    siteConfig: {
      alwaysOn: true
      linuxFxVersion: 'DOCKER|${dockerImageName}'
      appSettings: [
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_URL'
          value: '${containerRegistryName}.azurecr.io'
        }
        {
          name: 'DOCKER_REGISTRY_USERNAME'
          value: containerRegistryName
        }
        {
          name: 'DOCKER_REGISTRY_PASSWORD'
          value: listCredentials(containerRegistryName, '2020-11-01-preview').passwords[0].value
        }
        {
          name: 'DATABASE_URL'
          value: 'postgresql://${db.properties.administratorLogin}:${uriComponent(dbPassword)}@${db.properties.fullyQualifiedDomainName}/${dbName}?sslmode=require'
        }
        {
          name: 'AZURE_STORAGE_ACCOUNT_NAME'
          value: storageAccountName
        }
        {
          name: 'AZURE_STORAGE_ACCESS_KEY'
          value: listKeys(storageAccountName, '2021-04-01').keys[0].value
        }
        {
          name: 'AZURE_STORAGE_CONTAINER'
          value: 'files'
        }
      ]
    }
  }
  dependsOn: [
    appServicePlan
    containerRegistry
    webAppSubnet
  ]
}

resource webAppNetworkConfig 'Microsoft.Web/sites/networkConfig@2021-01-15' = {
  parent: webApp
  name: 'virtualNetwork'
  properties: {
    subnetResourceId: webAppSubnet.id
  }
}

var cdnProfileName = '${name}-cdn-profile'
resource cdnProfile 'Microsoft.Cdn/profiles@2020-09-01' = {
  location: 'Global'
  name: cdnProfileName
  properties: {}
  sku: {
    name: 'Standard_Microsoft'
  }
}

resource appCdnEndpoint 'Microsoft.Cdn/profiles/endpoints@2020-09-01' = {
  parent: cdnProfile
  location: 'Global'
  name: '${name}-app'
  properties: {
    deliveryPolicy: {
      rules: [
        {
          actions: [
            {
              name: 'UrlRedirect'
              parameters: {
                '@odata.type': '#Microsoft.Azure.Cdn.Models.DeliveryRuleUrlRedirectActionParameters'
                destinationProtocol: 'Https'
                redirectType: 'Moved'
              }
            }
          ]
          conditions: [
            {
              name: 'RequestScheme'
              parameters: {
                '@odata.type': '#Microsoft.Azure.Cdn.Models.DeliveryRuleRequestSchemeConditionParameters'
                matchValues: [
                  'HTTP'
                ]
                negateCondition: false
                operator: 'Equal'
              }
            }
          ]
          name: 'ForceSSL'
          order: 1
        }
      ]
    }
    isCompressionEnabled: true
    contentTypesToCompress: [
      'text/plain'
      'text/html'
      'text/css'
      'application/x-javascript'
      'text/javascript'
    ]
    isHttpAllowed: true
    isHttpsAllowed: true
    originHostHeader: webApp.properties.defaultHostName
    origins: [
      {
        name: 'web-origin'
        properties: {
          enabled: true
          hostName: webApp.properties.defaultHostName
          httpPort: 80
          httpsPort: 443
          originHostHeader: webApp.properties.defaultHostName
          priority: 1
          weight: 1000
        }
      }
    ]
    queryStringCachingBehavior: 'IgnoreQueryString'
    urlSigningKeys: []
  }
  dependsOn: [
    webApp
  ]
}

var asset_hostname = replace(replace(storageAccount.properties.primaryEndpoints.blob, 'https://', ''), '/', '')
resource asset_endpoint 'Microsoft.Cdn/profiles/endpoints@2020-09-01' = {
  parent: cdnProfile
  location: 'Global'
  name: '${name}-assets'
  properties: {
    isCompressionEnabled: true
    contentTypesToCompress: [
      'text/plain'
      'text/html'
      'text/css'
      'application/x-javascript'
      'text/javascript'
    ]
    isHttpAllowed: false
    isHttpsAllowed: true
    optimizationType: 'GeneralWebDelivery'
    originGroups: []
    originHostHeader: asset_hostname
    originPath: '/assets'
    origins: [
      {
        name: 'assets-origin'
        properties: {
          enabled: true
          hostName: asset_hostname
          originHostHeader: asset_hostname
          priority: 1
          weight: 1000
        }
      }
    ]
    queryStringCachingBehavior: 'IgnoreQueryString'
    urlSigningKeys: []
  }
  dependsOn: [
    storageAccount
  ]
}

resource webAppCustomDomain 'Microsoft.Cdn/profiles/endpoints/customdomains@2020-09-01' = if (!empty(domain)) {
  parent: appCdnEndpoint
  name: '${name}-custom-domain'
  properties: {
    hostName: domain
  }
  dependsOn: [
    cdnProfile
  ]
}