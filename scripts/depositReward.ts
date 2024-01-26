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

const MoveArkPackageId = env.MoveArkPackageId;
const MoveArkGame = env.MoveArkGame;

async function main() {
	const txb = new TransactionBlock();
	// == deposit_reward
	txb.moveCall({
		target: `${MoveArkPackageId}::moveark::deposit_reward`,
		arguments: [txb.object(MoveArkGame), txb.object('0x6')],
	});
	txb.setGasBudget(40_000_000)
	txb.setSender(keypair.getPublicKey().toSuiAddress());
	try {
		const result = await client.signAndExecuteTransactionBlock({
			transactionBlock: txb,
			signer: keypair,
			requestType: 'WaitForLocalExecution',
			options: {
				showEffects: false,
			},
		});
		console.log(result);
	} catch (error) {
		console.log(error)
	}
}

main();
