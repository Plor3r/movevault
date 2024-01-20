import { loadSync as loadEnvSync } from "https://deno.land/std/dotenv/mod.ts"
import { getFullnodeUrl, SuiClient } from 'npm:@mysten/sui.js/client';
import { Ed25519Keypair } from 'npm:@mysten/sui.js/keypairs/ed25519';
import { TransactionBlock } from 'npm:@mysten/sui.js/transactions';

const env = loadEnvSync();
const secret_key_mnemonics = env.SECRET_KEY_ED25519_1_MNEMONICS;
const keypair = Ed25519Keypair.deriveKeypair(secret_key_mnemonics);
console.log(keypair.getPublicKey().toSuiAddress())

const client = new SuiClient({
	url: getFullnodeUrl('testnet'),
});

const PACKAGE_ID = env.PACKAGE_ID;
const INSCRIPTION_ID = '0x0d8fd7b5903736ac7b564ec90d31efa4359452370f38f18f41ba27147847abce';

const MoveVault = '0x50349090140d32d78edbd0f5b595830742cb86668a0398233a6752301ed85986';
const MoveVaultGame = '0x1dbc8a64125fb6973caee2022f61692ec1fd3c395f04d43226c73269191e74ed';
const MoveVaultManagerCap = '0xc44cb9757fb243da5219d39e1daf3426c84aa85cbe167a1155b3dcd3f720fca2';

async function main() {
	const txb = new TransactionBlock();
	// == set pause
	// txb.moveCall({
	// 	target: `${MoveVault}::movevault::set_pause`,
	// 	arguments: [txb.object(MoveVaultManagerCap), txb.object(MoveVaultGame), txb.pure(false)],
	// });

	// == deposit
	const [move] = txb.moveCall({
		target: `${PACKAGE_ID}::movescription::do_split`,
		arguments: [txb.object(INSCRIPTION_ID), txb.pure(10000)],
	});
	txb.moveCall({
		target: `${MoveVault}::movevault::deposit`,
		arguments: [txb.object(MoveVaultGame), txb.object(move), txb.object('0x6')],
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
