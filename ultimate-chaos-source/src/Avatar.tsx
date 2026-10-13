import {Character} from './Character';import {AvatarOrnament} from './Artwork';
export function Avatar({index,frame='basic',size='normal'}:{index:number;frame?:string;size?:'normal'|'large'|'small'}){return <div className={`profile-avatar frame-${frame} avatar-${size}`}><Character index={index}/><AvatarOrnament frame={frame}/><span className="avatar-star">✦</span></div>;}
