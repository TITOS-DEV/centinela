const { CosmosClient } = require("@azure/cosmos");
const { DefaultAzureCredential } = require("@azure/identity");

// DefaultAzureCredential: en Azure usa la Managed Identity del Function App automáticamente.
// En local (func start), usa tu sesión de `az login`. Nunca hay una clave de Cosmos en ningún lado.
const credential = new DefaultAzureCredential();

const client = new CosmosClient({
  endpoint: process.env.COSMOS_ENDPOINT,
  aadCredentials: credential,
});

const database = client.database(process.env.COSMOS_DATABASE || "centinela");
const transactionsContainer = database.container(process.env.COSMOS_CONTAINER || "transactions");

module.exports = { transactionsContainer };
