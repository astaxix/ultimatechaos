import {useEffect} from 'react';
export function DialogFocus({onClose}:{onClose:()=>void}){
 useEffect(()=>{
  const root=document.querySelector('.hub-modal') as HTMLElement|null;if(!root)return;
  const previous=document.activeElement as HTMLElement;const controls=()=>Array.from(root.querySelectorAll<HTMLElement>('button:not(:disabled),input:not(:disabled),[tabindex="0"]'));
  controls()[0]?.focus();const overflow=document.body.style.overflow;document.body.style.overflow='hidden';
  function key(e:KeyboardEvent){if(e.key==='Escape'){e.preventDefault();onClose();}if(e.key==='Tab'){const all=controls(),first=all[0],last=all.at(-1);if(e.shiftKey&&document.activeElement===first){e.preventDefault();last?.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first?.focus();}}}
  document.addEventListener('keydown',key);return()=>{document.removeEventListener('keydown',key);document.body.style.overflow=overflow;previous?.focus();};
 },[onClose]);return null;
}
