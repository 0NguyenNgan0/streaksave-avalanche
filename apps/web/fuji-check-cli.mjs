import { createPublicClient, http, formatUnits, parseUnits } from 'viem';
import { readFileSync } from 'node:fs';
const rpc = 'https://api.avax-test.network/ext/bc/C/rpc';
const usdc='0x1aaB5693678b18753dCFD5096f497031c1A1f126';
const streak='0xE71Ae741c3bEe9f7F21057d825FE7dA8984406f9';
const deployer='0x8986EC1B5E6Ca6Ceeb5ea608E8BA718b72D7Fd67';
const outsider='0x000000000000000000000000000000000000dEaD';
const abi=JSON.parse(readFileSync(new URL('../../shared/abi/StreakSavings.json', import.meta.url)));
const tokenAbi=JSON.parse(readFileSync(new URL('../../shared/abi/MockUSDC.json', import.meta.url)));
const c=createPublicClient({transport:http(rpc)});
const read=(address,contractAbi,functionName,args=[])=>c.readContract({address,abi:contractAbi,functionName,args});
const r=(name,args=[])=>read(streak,abi,name,args);
const t=(name,args=[])=>read(usdc,tokenAbi,name,args);
const assert=(condition,message)=>{ if(!condition) throw Error(message); console.log('PASS: '+message) };
async function run(){
  assert(await c.getChainId()===43113,'Chain ID 43113');
  for(const [name,address] of [['MockUSDC',usdc],['StreakSavings',streak]]){
    const code=await c.getBytecode({address}); assert(!!code&&code!=='0x',name+' bytecode');
  }
  const linked=await r('usdc');assert(linked.toLowerCase()===usdc.toLowerCase(),'Correct USDC linkage');
  assert(Number(await t('decimals'))===6,'MockUSDC has six decimals');
  const provider=await r('yieldProvider');assert(provider.toLowerCase()===deployer.toLowerCase(),'Provider matches deployer');
  const duration=await r('epochDuration');assert(duration===60n,'Epoch duration 60 seconds');
  const epoch=await r('currentEpoch'), countdown=await r('timeUntilNextEpoch');
  const principal=await r('principalOf',[deployer]);const balance=await t('balanceOf',[deployer]);
  const allowance=await t('allowance',[deployer,streak]);
  console.log('Current epoch',epoch.toString(),'countdown',countdown.toString(),'s');
  console.log('Deployer principal',formatUnits(principal,6),'MockUSDC; balance',formatUnits(balance,6),'MockUSDC; allowance',formatUnits(allowance,6));
  await c.simulateContract({address:usdc,abi:tokenAbi,functionName:'approve',args:[streak,parseUnits('5',6)],account:deployer});
  console.log('PASS: approve simulation (no state change)');
  try { await c.simulateContract({address:streak,abi,functionName:'deposit',args:[parseUnits('5',6)],account:deployer});
    console.log('OBSERVED: deposit simulation permitted');
  } catch(e) { console.log('OBSERVED: deposit simulated revert, possibly allowance/balance. Allowance at read:',formatUnits(allowance,6)); console.log('Revert:',e.shortMessage??e.message); }
  if(provider.toLowerCase()===outsider.toLowerCase()) throw Error('Outsider unexpectedly authorized');
  let denied=false;
  try{await c.simulateContract({address:streak,abi,functionName:'addMockYield',args:[parseUnits('5',6)],account:outsider});}
  catch(e){denied=true;console.log('PASS: outsider addMockYield rejected');}
  assert(denied,'Yield access control simulated');
  console.log('=== FUJI READ + SIMULATION COMPLETED; ZERO TRANSACTIONS BROADCAST ===');
}
run().catch(e=>{console.error('FAIL:',e.shortMessage??e.message);process.exitCode=1});
