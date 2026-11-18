"use client";

import { useMemo, useState } from "react";
import { formatUnits, parseUnits, zeroAddress, type Address, type Hash } from "viem";
import { useAccount, usePublicClient, useReadContract, useWriteContract } from "wagmi";
import { contractsConfigured, erc20Abi, STREAK_CONTRACT, streakSavingsAbi, USDC_CONTRACT } from "@/lib/contracts";

const USDC_DECIMALS = 6;
type ActionState = "idle"|"approving"|"depositing"|"claiming"|"withdrawing"|"success"|"error";

function formatUsdc(value?: bigint) {
  if (value === undefined) return "—";
  const n = Number(formatUnits(value, USDC_DECIMALS));
  return n.toLocaleString(undefined, { maximumFractionDigits: 2 });
}

function formatCountdown(value?: bigint) {
  if (value === undefined) return "—";
  const t = Number(value), h=Math.floor(t/3600), m=Math.floor((t%3600)/60), s=t%60;
  return h>0 ? `${h}h ${String(m).padStart(2,"0")}m` : `${String(m).padStart(2,"0")}:${String(s).padStart(2,"0")}`;
}

export function useStreakSave() {
  const { address } = useAccount();
  const publicClient = usePublicClient();
  const { writeContractAsync } = useWriteContract();
  const [actionState,setActionState]=useState<ActionState>("idle");
  const [lastHash,setLastHash]=useState<Hash>();
  const [error,setError]=useState<string>();
  const enabled=Boolean(address&&contractsConfigured);
  const contractEnabled=Boolean(contractsConfigured);
  const user=address??zeroAddress;
  const streakAddress=STREAK_CONTRACT??zeroAddress;
  const usdcAddress=USDC_CONTRACT??zeroAddress;

  const principal=useReadContract({address:streakAddress,abi:streakSavingsAbi,functionName:"principalOf",args:[user],query:{enabled}});
  const streak=useReadContract({address:streakAddress,abi:streakSavingsAbi,functionName:"effectiveStreakOf",args:[user],query:{enabled}});
  const reward=useReadContract({address:streakAddress,abi:streakSavingsAbi,functionName:"rewardOf",args:[user],query:{enabled}});
  const balance=useReadContract({address:usdcAddress,abi:erc20Abi,functionName:"balanceOf",args:[user],query:{enabled}});
  const allowance=useReadContract({address:usdcAddress,abi:erc20Abi,functionName:"allowance",args:[user,streakAddress],query:{enabled}});
  const epoch=useReadContract({address:streakAddress,abi:streakSavingsAbi,functionName:"currentEpoch",query:{enabled:contractEnabled}});
  const countdown=useReadContract({address:streakAddress,abi:streakSavingsAbi,functionName:"timeUntilNextEpoch",query:{enabled:contractEnabled,refetchInterval:1000}});

  async function wait(hash:Hash){setLastHash(hash);if(!publicClient)throw new Error("Fuji public client is unavailable.");const r=await publicClient.waitForTransactionReceipt({hash});if(r.status!=="success")throw new Error("Transaction reverted.");}
  async function refetchAll(){await Promise.all([principal.refetch(),streak.refetch(),reward.refetch(),balance.refetch(),allowance.refetch(),epoch.refetch(),countdown.refetch()]);}
  function guard(){if(!address)throw new Error("Connect your wallet first.");if(!contractsConfigured||!STREAK_CONTRACT||!USDC_CONTRACT)throw new Error("Contract addresses are not configured yet.");}
  async function run(state:ActionState,fn:()=>Promise<void>){try{setError(undefined);setActionState(state);await fn();await refetchAll();setActionState("success");}catch(e){setError(e instanceof Error?e.message:"Transaction failed.");setActionState("error");}}
  async function approve(amount:string){await run("approving",async()=>{guard();const raw=parseUnits(amount,USDC_DECIMALS);const hash=await writeContractAsync({address:USDC_CONTRACT as Address,abi:erc20Abi,functionName:"approve",args:[STREAK_CONTRACT as Address,raw]});await wait(hash);});}
  async function deposit(amount:string){await run("depositing",async()=>{guard();const raw=parseUnits(amount,USDC_DECIMALS);const hash=await writeContractAsync({address:STREAK_CONTRACT as Address,abi:streakSavingsAbi,functionName:"deposit",args:[raw]});await wait(hash);});}
  async function claimReward(){await run("claiming",async()=>{guard();const hash=await writeContractAsync({address:STREAK_CONTRACT as Address,abi:streakSavingsAbi,functionName:"claimReward"});await wait(hash);});}
  async function withdraw(amount:string){await run("withdrawing",async()=>{guard();const raw=parseUnits(amount,USDC_DECIMALS);const hash=await writeContractAsync({address:STREAK_CONTRACT as Address,abi:streakSavingsAbi,functionName:"withdraw",args:[raw]});await wait(hash);});}

  const rawAllowance=(allowance.data as bigint|undefined)??0n;
  const rawPrincipal=(principal.data as bigint|undefined)??0n;
  const rawReward=(reward.data as bigint|undefined)??0n;
  const rawStreak=streak.data as bigint|undefined;
  const rawEpoch=epoch.data as bigint|undefined;
  const rawCountdown=countdown.data as bigint|undefined;
  const values=useMemo(()=>({principal:formatUsdc(rawPrincipal),streak:rawStreak===undefined?"—":rawStreak.toString(),reward:formatUsdc(rawReward),balance:formatUsdc(balance.data as bigint|undefined),epoch:rawEpoch===undefined?"—":rawEpoch.toString(),epochCountdown:formatCountdown(rawCountdown),rawAllowance}),[rawPrincipal,rawStreak,rawReward,balance.data,rawEpoch,rawCountdown,rawAllowance]);
  return {configured:contractsConfigured,address,actionState,lastHash,error,values,raw:{principal:rawPrincipal,reward:rawReward,allowance:rawAllowance,effectiveStreak:rawStreak??0n,currentEpoch:rawEpoch??0n,secondsUntilNextEpoch:rawCountdown??0n},approve,deposit,claimReward,withdraw,refresh:refetchAll};
}
