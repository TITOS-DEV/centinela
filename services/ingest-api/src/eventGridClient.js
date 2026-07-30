const { EventGridPublisherClient } = require("@azure/eventgrid");
const { DefaultAzureCredential } = require("@azure/identity");

// Ver cosmosClient.js: managedIdentityClientId selecciona la identidad
// user-assigned de este Container App especificamente.
const credential = new DefaultAzureCredential({
  managedIdentityClientId: process.env.MANAGED_IDENTITY_CLIENT_ID,
});

// "EventGrid" schema porque el topic se creó con inputSchema: EventGridSchema (ver eventgrid.bicep).
const client = new EventGridPublisherClient(
  process.env.EVENTGRID_TOPIC_ENDPOINT,
  "EventGrid",
  credential
);

module.exports = { eventGridClient: client };
