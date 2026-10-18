/** Serialize network writes and coalesce rapid changes without dropping the last intent. */
export class LatestIntentQueue<T,R>{private next:T|undefined;private running=false;private epoch=0;private disposed=false;
 constructor(private send:(value:T)=>Promise<R>,private success:(result:R,value:T)=>void,private failure:(error:unknown,value:T)=>void,private busy:(active:boolean)=>void){}
 get active(){return this.running;}
 submit(value:T){if(this.disposed)return;this.next=value;if(!this.running)void this.drain();}
 cancel(){this.next=undefined;this.epoch++;}
 dispose(){this.cancel();this.disposed=true;}
 private async drain(){this.running=true;this.busy(true);try{while(this.next!==undefined&&!this.disposed){const value=this.next,epoch=this.epoch;this.next=undefined;try{const result=await this.send(value);if(epoch===this.epoch&&!this.disposed)this.success(result,value);}catch(error){if(epoch===this.epoch&&!this.disposed&&this.next===undefined)this.failure(error,value);}}}finally{this.running=false;if(!this.disposed)this.busy(false);}}
}
