const slides=[
 ['assets/bully-wide.jpeg','BULLY / WIDE HUD'],['assets/bully-compact.jpeg','BULLY / COMPACT HUD'],['assets/maxpayne-compact.jpeg','MAX PAYNE / COMPACT HUD'],['assets/maxpayne-full-hud.jpeg','MAX PAYNE / FULL HUD'],['assets/bully-full-hud.jpeg','BULLY / FULL HUD'],['assets/maxpayne-fps.jpeg','MAX PAYNE / FPS MODE'],['assets/maxpayne-top.jpeg','MAX PAYNE / TOP HUD']
];
let index=0, timer;
const img=document.getElementById('sliderImage'), heroImg=document.getElementById('heroScreen'), title=document.getElementById('slideTitle'), count=document.getElementById('slideCount'), bar=document.getElementById('progressBar'), pct=document.getElementById('progressText'), thumbs=document.getElementById('thumbs');

slides.forEach((s,i)=>{
  const b=document.createElement('button');
  b.className='thumb'+(i===0?' active':'');
  b.innerHTML=`<img src="${s[0]}" alt="">`;
  b.onclick=()=>go(i);
  thumbs.appendChild(b);
});

function swapImage(el, src){
  if(!el) return;
  el.classList.add('changing');
  setTimeout(()=>{
    el.src=src;
    el.onload=()=>el.classList.remove('changing');
  },150);
}

function go(n){
  index=(n+slides.length)%slides.length;
  swapImage(img,slides[index][0]);
  swapImage(heroImg,slides[index][0]);
  title.textContent=slides[index][1];
  count.textContent=String(index+1).padStart(2,'0')+' / 07';
  const p=Math.round((index+1)/slides.length*100);
  bar.style.width=p+'%';
  pct.textContent=p+'%';
  document.querySelectorAll('.thumb').forEach((x,j)=>x.classList.toggle('active',j===index));
  restart();
}

document.getElementById('prev').onclick=()=>go(index-1);
document.getElementById('next').onclick=()=>go(index+1);
function restart(){clearInterval(timer);timer=setInterval(()=>go(index+1),5000)}
restart();

let fps=60;
setInterval(()=>{
  fps=58+Math.floor(Math.random()*4);
  document.getElementById('liveFps').textContent=fps;
  document.getElementById('liveFt').textContent=(1000/fps).toFixed(1)+'ms';
},900);

const hero=document.querySelector('.game-device');
const heroRight=document.querySelector('.hero-right');
heroRight.addEventListener('pointermove',e=>{
  if(innerWidth<800)return;
  const r=e.currentTarget.getBoundingClientRect(),x=(e.clientX-r.left)/r.width-.5,y=(e.clientY-r.top)/r.height-.5;
  hero.style.transform=`rotateY(${-5+x*5}deg) rotateX(${3-y*4}deg) rotateZ(-1.5deg) translateY(-4px)`;
});
heroRight.addEventListener('pointerleave',()=>hero.style.transform='rotateY(-5deg) rotateX(3deg) rotateZ(-1.5deg)');

const mouseGlow=document.querySelector('.mouse-glow');
if(mouseGlow && matchMedia('(pointer:fine)').matches){
  let glowX=innerWidth/2, glowY=innerHeight/2, targetX=glowX, targetY=glowY, raf;
  const renderGlow=()=>{
    glowX += (targetX-glowX)*0.12;
    glowY += (targetY-glowY)*0.12;
    mouseGlow.style.transform=`translate3d(${glowX}px,${glowY}px,0) translate3d(-50%,-50%,0)`;
    raf=requestAnimationFrame(renderGlow);
  };
  window.addEventListener('pointermove',e=>{targetX=e.clientX;targetY=e.clientY;mouseGlow.classList.add('active')},{passive:true});
  window.addEventListener('pointerleave',()=>mouseGlow.classList.remove('active'));
  window.addEventListener('blur',()=>mouseGlow.classList.remove('active'));
  renderGlow();
}
