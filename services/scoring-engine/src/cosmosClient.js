const { CosmosClient } = require("@azure/cosmos");
const { DefaultAzureCredential } = require("@azure/identity");

// Misma filosofia que ingest-api: Managed Identity en Azure, `az login` en
// local. managedIdentityClientId selecciona la identidad user-assigned de
// este Container App especificamente (ver services/*/src/cosmosClient.js).
const credential = new DefaultAzureCredential({
  managedIdentityClientId: process.env.MANAGED_IDENTITY_CLIENT_ID,
});

const client = new CosmosClient({
  endpoint: process.env.COSMOS_ENDPOINT,
  aadCredentials: credential,
});

const database = client.database(process.env.COSMOS_DATABASE || "centinela");
const transactionsContainer = database.container(process.env.COSMOS_CONTAINER || "transactions");
const casesContainer = database.container(process.env.COSMOS_CASES_CONTAINER || "cases");

module.exports = { transactionsContainer, casesContainer };
