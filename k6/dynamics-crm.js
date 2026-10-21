import http from 'k6/http';
import { check, fail, sleep } from 'k6';

const crmUrl = (__ENV.CRM_BASE_URL || '').replace(/\/+$/, '');
const tenantId = __ENV.CRM_TENANT_ID || '';
const clientId = __ENV.CRM_CLIENT_ID || '';
const clientSecret = __ENV.CRM_CLIENT_SECRET || '';
const apiVersion = __ENV.CRM_API_VERSION || 'v9.2';
const lookupField = (__ENV.LOOKUP_FIELD || 'email').toLowerCase();
const emailDomain = __ENV.CONTACT_EMAIL_DOMAIN || 'loadtest.example.invalid';
const telephonePrefix = __ENV.CONTACT_TELEPHONE_PREFIX || '';
const runId = (__ENV.TEST_RUN_ID || String(Date.now())).replace(/[^a-zA-Z0-9-]/g, '-');
const runIdDigits = [...runId]
  .reduce((value, character) => (value * 31 + character.charCodeAt(0)) % 1000000, 0)
  .toString()
  .padStart(6, '0');
const apiRoot = `${crmUrl}/api/data/${apiVersion}`;
const iterationCount = Number(__ENV.ITERATIONS || 1);
const virtualUsers = Number(__ENV.VUS || 1);
const maxDuration = __ENV.MAX_DURATION || '10m';

if (!crmUrl || !tenantId || !clientId || !clientSecret) {
  throw new Error('Set CRM_BASE_URL, CRM_TENANT_ID, CRM_CLIENT_ID, and CRM_CLIENT_SECRET.');
}

if (lookupField !== 'emailaddress1' && lookupField !== 'msobilephone') {
  throw new Error('LOOKUP_FIELD must be either "email" or "telephone".');
}

if (lookupField === 'telephone' && !telephonePrefix) {
  throw new Error('Set CONTACT_TELEPHONE_PREFIX when LOOKUP_FIELD is "telephone".');
}

if (!Number.isInteger(iterationCount) || iterationCount < 1 ||
    !Number.isInteger(virtualUsers) || virtualUsers < 1) {
  throw new Error('ITERATIONS and VUS must be positive integers.');
}

export const options = {
  scenarios: {
    crmContactPhonecall: {
      executor: 'shared-iterations',
      vus: virtualUsers,
      iterations: iterationCount,
      maxDuration,
    },
  },
};

let accessToken;
let tokenExpiresAt = 0;

function getAccessToken() {
  if (accessToken && Date.now() < tokenExpiresAt) {
    return accessToken;
  }

  const tokenUrl = `https://login.microsoftonline.com/${encodeURIComponent(tenantId)}/oauth2/v2.0/token`;
  const response = http.post(tokenUrl, {
    client_id: clientId,
    client_secret: clientSecret,
    scope: `${crmUrl}/.default`,
    grant_type: 'client_credentials',
  });

  if (!check(response, { 'token request succeeded': (res) => res.status === 200 })) {
    fail(`Microsoft Entra token request failed with HTTP ${response.status}.`);
  }

  const token = response.json();
  if (!token.access_token || !token.expires_in) {
    fail('Microsoft Entra token response did not include an access token and expiry.');
  }

  accessToken = token.access_token;
  tokenExpiresAt = Date.now() + (Number(token.expires_in) - 60) * 1000;
  return accessToken;
}

function apiHeaders() {
  return {
    Authorization: `Bearer ${getAccessToken()}`,
    Accept: 'application/json',
    'Content-Type': 'application/json',
    'OData-Version': '4.0',
    'OData-MaxVersion': '4.0',
    Prefer: 'return=representation',
  };
}

function requireStatus(response, expectedStatuses, operation) {
  if (!check(response, {
    [`${operation} succeeded`]: (res) => expectedStatuses.includes(res.status),
  })) {
    fail(`${operation} failed with HTTP ${response.status}.`);
  }
}

function getCreatedRecordId(response, entityName, idField) {
  const entityIdHeader = Object.keys(response.headers)
    .find((name) => name.toLowerCase() === 'odata-entityid');
  const entityId = entityIdHeader && response.headers[entityIdHeader];
  const match = entityId && entityId.match(new RegExp(`${entityName}\\(([^)]+)\\)`));
  if (match) {
    return match[1];
  }

  const body = response.body ? response.json() : null;
  if (body && body[idField]) {
    return body[idField];
  }

  fail(`${entityName} create response did not include a record ID.`);
}

function contactDetails() {
  const uniquePart = `${runId}-vu${__VU}-iter${__ITER}`;
  const email = `loadtest+${uniquePart}@${emailDomain}`;
  const phone = `${telephonePrefix}${runIdDigits}${String(__VU).padStart(3, '0')}${String(__ITER).padStart(6, '0')}`;
  const lookupValue = lookupField === 'email' ? email : phone;
  const lookupAttribute = lookupField === 'email' ? 'emailaddress1' : 'telephone1';

  return {
    email,
    phone,
    lookupValue,
    lookupAttribute,
    uniquePart,
  };
}

function findContact(details, headers) {
  const escapedValue = details.lookupValue.replace(/'/g, "''");
  const filter = `${details.lookupAttribute} eq '${escapedValue}'`;
  const url = `${apiRoot}/contacts?$select=contactid&$filter=${encodeURIComponent(filter)}&$top=1`;
  const response = http.get(url, { headers, tags: { operation: 'lookup-contact' } });
  requireStatus(response, [200], 'Contact lookup');

  const contacts = response.json().value;
  if (!Array.isArray(contacts)) {
    fail('Contact lookup response did not include a results array.');
  }

  return contacts.length > 0 ? contacts[0].contactid : null;
}

function createContact(details, headers) {
  const response = http.post(
    `${apiRoot}/contacts`,
    JSON.stringify({
      firstname: 'Load',
      lastname: `Test ${details.uniquePart}`,
      emailaddress1: details.email,
      telephone1: details.phone,
    }),
    { headers, tags: { operation: 'create-contact' } },
  );
  requireStatus(response, [200, 201, 204], 'Contact creation');
  return getCreatedRecordId(response, 'contacts', 'contactid');
}

function createPhonecall(contactId, headers) {
  const response = http.post(
    `${apiRoot}/phonecalls`,
    JSON.stringify({
      subject: 'k6 load test phone call',
      description: 'Created by the Dynamics CRM k6 load test.',
      phonenumber: '5550100',
      directioncode: true,
      phonecall_activity_parties: [
        {
          participationtypemask: 2,
          'partyid_contact@odata.bind': `/contacts(${contactId})`,
        },
      ],
    }),
    { headers, tags: { operation: 'create-phonecall' } },
  );
  requireStatus(response, [200, 201, 204], 'Phone call creation');
  return getCreatedRecordId(response, 'phonecalls', 'activityid');
}

function updatePhonecall(phonecallId, headers) {
  const response = http.patch(
    `${apiRoot}/phonecalls(${phonecallId})`,
    JSON.stringify({
      subject: 'k6 load test phone call - updated',
      description: 'Updated by the Dynamics CRM k6 load test.',
    }),
    { headers, tags: { operation: 'update-phonecall' } },
  );
  requireStatus(response, [200, 204], 'Phone call update');
}

export default function () {
  const headers = apiHeaders();
  const details = contactDetails();
  const contactId = findContact(details, headers) || createContact(details, headers);
  const phonecallId = createPhonecall(contactId, headers);

  sleep(60 + Math.floor(Math.random() * 61));

  updatePhonecall(phonecallId, headers);
}
