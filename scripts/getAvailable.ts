import { loadSync as loadEnvSync } from "https://deno.land/std/dotenv/mod.ts"
import { getFullnodeUrl, SuiClient } from 'npm:@mysten/sui.js/client';
import { Ed25519Keypair } from 'npm:@mysten/sui.js/keypairs/ed25519';
import { TransactionBlock } from 'npm:@mysten/sui.js/transactions';

const env = loadEnvSync();
const secret_key_mnemonics = env.SECRET_KEY_ED25519_1_MNEMONICS;
const keypair = Ed25519Keypair.deriveKeypair(secret_key_mnemonics);
console.log(keypair.getPublicKey().toSuiAddress())

const client = new SuiClient({
    url: getFullnodeUrl(env.Network),
});

const MoveVaultPackageId = env.MoveVaultPackageId;
const UserDataObjectId = "0xad697f0d8d508c8a5428ffa91f41f3b3ff05e22946e7e67897dcfccbedf9f56a";

async function main() {
    const txb = new TransactionBlock();
    txb.moveCall({
        target: `${MoveVaultPackageId}::movevault::available`,
        arguments: [txb.object(UserDataObjectId), txb.object('0x6')],
    })
    const result = await client.devInspectTransactionBlock({
        transactionBlock: txb,
        sender: '0x0000000000000000000000000000000000000000000000000000000000000000',
    });
    console.log(result.results);
}

main();
