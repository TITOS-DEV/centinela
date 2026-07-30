const { CosmosClient } = require("@azure/cosmos");
const { DefaultAzureCredential } = require("@azure/identity");

// DefaultAzureCredential: en Azure usa la identidad administrada asignada por
// el usuario del Container App (MANAGED_IDENTITY_CLIENT_ID le indica CUAL,
// porque hay mas de una identidad posible en la suscripcion). En local
// (docker run / npm start), usa tu sesion de `az login`. Nunca hay una clave
// de Cosmos en ningun lado.
const credential = new DefaultAzureCredential({
  managedIdentityClientId: process.env.MANAGED_IDENTITY_CLIENT_ID,
});

const client = new CosmosClient({
  endpoint: process.env.COSMOS_ENDPOINT,
  aadCredentials: credential,
});

const database = client.database(process.env.COSMOS_DATABASE || "centinela");
const transactionsContainer = database.container(process.env.COSMOS_CONTAINER || "transactions");

module.exports = { transactionsContainer };
