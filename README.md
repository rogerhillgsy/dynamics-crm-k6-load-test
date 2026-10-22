# Dynamics CRM load testing

This repository contains two implementations of the Dynamics 365 / Dataverse API scenario:

- `k6/dynamics-crm.js` for the manually triggered Azure Container Apps Job.
- `jmeter/dynamics-crm.jmx` for Azure Load Testing (JMeter 5.6.3).

The JMeter plan follows the same workflow:

1. Look up a contact using a generated email address or telephone number.
2. Create the contact if no match is found.
3. Create a phone call with the contact as a participant.
4. Wait for a random 60-120 seconds.
5. Update the phone call.

The plan caches each virtual user's Microsoft Entra access token and refreshes it before expiry. API requests have response assertions, and a failed lookup or create stops that user's thread rather than continuing with invalid record IDs.

## Prerequisites

- An Azure Load Testing resource and permission to create and run tests.
- A Microsoft Entra application using client-credentials authentication and a Dynamics application user with least-privilege access to look up/create contacts and create/update phone calls.
- A non-production Dynamics environment with an email domain and, when using telephone lookup, telephone prefix suitable for synthetic records.

Keep load testing within an authorized environment and Dynamics service-protection limits.

## Configure Azure Load Testing

1. In the Azure portal, open the Azure Load Testing resource and create a test by uploading [`jmeter/dynamics-crm.jmx`](./jmeter/dynamics-crm.jmx).
2. Upload [`jmeter/user.properties`](./jmeter/user.properties) as the JMeter user properties file. Set `VUS` and `ITERATIONS` to the intended virtual-user count and iterations per user. Each iteration includes a 60-120 second wait; allow enough test duration for all iterations to finish.
3. In the test's **Parameters** configuration, add these non-secret environment variables:

   | Name | Example | Notes |
   | --- | --- | --- |
   | `CRM_BASE_URL` | `https://example.crm.dynamics.com` | Dynamics environment URL, without a trailing slash. |
   | `CRM_TENANT_ID` | `00000000-0000-0000-0000-000000000000` | Microsoft Entra tenant ID. |
   | `CRM_CLIENT_ID` | `00000000-0000-0000-0000-000000000000` | Application client ID. |
   | `LOOKUP_FIELD` | `email` | `email` or `telephone`. |
   | `CONTACT_EMAIL_DOMAIN` | `loadtest.example.invalid` | Synthetic contact email domain. Use a domain accepted by your environment. |
   | `CONTACT_TELEPHONE_PREFIX` | `+1555` | Required for telephone lookup; use test numbers only. |
   | `CRM_API_VERSION` | `v9.2` | Optional; defaults to `v9.2`. |
   | `TEST_RUN_ID` | `smoke-2026-10` | Optional; use a new value to generate a distinct set of contact identities. |

   Set `LOOKUP_FIELD=telephone` and provide `CONTACT_TELEPHONE_PREFIX` to look up contacts by telephone. For email lookup, the plan uses a unique email address in the configured domain.

4. Add a load-test secret named **`dynamicsCrmClientSecret`**. Prefer an Azure Key Vault secret reference and grant the Azure Load Testing resource's managed identity permission to read it. The JMeter plan reads it with Azure Load Testing's `__GetSecret` function; do not put credentials in the JMX file, `user.properties`, or environment-variable values.
5. Choose the load pattern and test duration in Azure Load Testing, then run the test. Review request failures and response-time metrics for the individual lookup, create, and update samplers.

`VUS` and `ITERATIONS` are JMeter properties, set in the uploaded user properties file. Environment values control the Dynamics endpoint and scenario behavior; the CRM client secret is passed separately as a load-test secret.

## Local checks

The test-plan validator checks JMX XML structure and verifies the request sequence and 60-120 second timer without making API calls:

```powershell
python jmeter/validate.py
```

Azure Load Testing's `__GetSecret` function is available when the plan runs in that service. For a local JMeter smoke test, make a temporary copy of the JMX and replace the `CRM_CLIENT_SECRET` user-defined variable's `__GetSecret` call with a local environment-variable lookup; set the remaining environment variables locally and never commit the copy or credentials.

## GitHub Actions

The validation workflow checks the k6 script, Docker image, Bicep templates, and JMeter plan. It does not contact Dynamics or require credentials.
