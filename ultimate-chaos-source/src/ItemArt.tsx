import {MaterialPart} from './AvatarMaterials';import {consumable} from './consumables';
export function ItemArt({id}:{id:string}){const item=consumable(id);return item?<span className="item-art" role="img" aria-label={item.name}><svg viewBox="0 0 140 140" aria-hidden="true"><MaterialPart sheet="consumables" index={item.art} x={8} y={8} width={124} height={124}/></svg></span>:null;}
