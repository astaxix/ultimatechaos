import {CosmeticFrame} from './CosmeticFrame';
import {Traveler} from './Traveler';import type {Look} from './appearance';import {AvatarOrnament} from './Artwork';
export function Avatar({index:_index,appearance,frame='basic',size='normal'}:{index:number;appearance?:Partial<Look>|null;frame?:string;size?:'normal'|'large'|'small'}){return <div className={`profile-avatar frame-${frame} avatar-${size}`}><Traveler look={appearance} portrait/><AvatarOrnament frame={frame}/><CosmeticFrame id={frame}/><span className="avatar-star">✦</span></div>;}
