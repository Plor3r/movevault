import { loadSync as loadEnvSync } from "https://deno.land/std/dotenv/mod.ts"
import { SuiClient, getFullnodeUrl } from "npm:@mysten/sui.js/client";

const env = loadEnvSync();
const MoveArkPackageId = env.MoveArkPackageId;
const MoveArkGame = env.MoveArkGame;

const client = new SuiClient({
    url: getFullnodeUrl(env.Network),
});

const getSuiDynamicFields = async (
    id: string,
    dynamic_field_name: string,
) => {
    const parent_obj = await client.getObject({
        id,
        options: {
            showContent: true,
        },
    })
    // console.log(parent_obj)
    const dynamic_field_key =
        // @ts-ignore
        parent_obj.data?.content?.fields[dynamic_field_name].fields.id.id ?? ''
    if (!dynamic_field_key) {
        throw new Error(`${dynamic_field_name} not found`)
    }
    // console.log(dynamic_field_key)

    const collection_keys = await client.getDynamicFields({
        parentId: dynamic_field_key,
    })
    // console.log(collection_keys)
    const result = []
    for (const key of collection_keys.data) {
        const obj = await getSuiObject(key.objectId)
        // console.log(obj)
        // const key = obj.data?.content?.fields.name
        const user_data_obj = obj.data?.content?.fields.value
        // console.log(user_data_obj)
        // @ts-ignore
        result.push(user_data_obj.fields)
    }
    return result
}

const getSuiObject = (id: string) => {
    return client.getObject({
        id,
        options: {
            showContent: true,
        },
    })
}

const user_datas = await getSuiDynamicFields(MoveArkGame, 'user_datas')

console.log(user_datas);

// ticks.forEach(item => {
//     console.log(item['tick']);
//     console.log(item['id']['id']);
// });