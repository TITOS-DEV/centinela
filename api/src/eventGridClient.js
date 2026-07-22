const { EventGridPublisherClient } = require("@azure/eventgrid");
const { DefaultAzureCredential } = require("@azure/identity");

const credential = new DefaultAzureCredential();

// "EventGrid" schema porque el topic se creó con inputSchema: EventGridSchema (ver eventgrid.bicep).
const client = new EventGridPublisherClient(
  process.env.EVENTGRID_TOPIC_ENDPOINT,
  "EventGrid",
  credential
);

module.exports = { eventGridClient: client };
