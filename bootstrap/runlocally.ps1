$env:CRM_BASE_URL = "https://rbhcuk.crm11.dynamics.com"
$env:CRM_TENANT_ID =  "0699e5de-8e14-4867-bd8f-fef147a2b3e2"
$env:CRM_CLIENT_ID = "e8c1ab45-d373-48bf-98b0-fa9a82008151"
$env:CRM_CLIENT_SECRET = "$envClientSecret"
$env:LOOKUP_FIELD = "emailaddress1"
$env:ITERATIONS = "1"
$env:VUS = "1"
$env:TEST_RUN_ID = "local-smoke-test"

docker run --rm `
  --env CRM_BASE_URL `
  --env CRM_TENANT_ID `
  --env CRM_CLIENT_ID `
  --env CRM_CLIENT_SECRET `
  --env LOOKUP_FIELD `
  --env ITERATIONS `
  --env VUS `
  --env TEST_RUN_ID `
  dynamics-crm-k6:local