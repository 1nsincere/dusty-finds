import random, statistics
R=['C','U','R','E','L']
T1={'C':[12,14,16,18],'U':[32,35,38],'R':[80,85],'E':[180,170],'L':[450]}
T2={'C':[70,75],'U':[170,180],'R':[400,420],'E':[900],'L':[2250]}
STEPS={'C':2,'U':3,'R':4,'E':5,'L':5}
CR={'Starter':(50,T1,[.60,.25,.10,.04,.01],1),'Flea':(300,T2,[.55,.27,.12,.05,.01],5)}
XPR={'C':10,'U':20,'R':40,'E':80,'L':160}
def xpneed(L): return round(40*L**1.6)
def ev(crate):
    p,T,o,_=CR[crate]; return sum(o[i]*statistics.mean(T[r]) for i,r in enumerate(R))
for c in CR: print(c,'EV base/item',round(ev(c),1))
cum=0
for L in range(1,21):
    cum+=xpneed(L)
    if L in (4,5,9,10,11,12,15,19): print('cum XP to reach',L+1,cum)
UP=[ # name,cost,level,effect
('Shelf1',120,1),('Storage1',100,1),('Brush1',150,1),('Polisher1',200,2),('Toolkit1',250,2),('Sign1',300,2),
('Plant',160,1),('Rug',150,1),('Shelf2',900,3),('Storage2',1000,4),('BackRoom',2500,4),('Posters',200,1),('Lamps',400,1),
('Brush2',1500,5),('Polisher2',1800,5),('Toolkit2',2000,6),('Sign2',2500,6),('Neon',1500,1),('Shelf3',4000,7),('Storage3',5000,8),
('FishTank',3000,1),('Brush3',8000,10),('Polisher3',8500,10),('Toolkit3',9000,11),('Showroom',20000,10),('Fountain',10000,10),('Sign3',12000,12)]
REQ={'FishTank':'BackRoom','Fountain':'Showroom'} # same as `requires` in Shared/Config/Upgrades.luau: must own this first
def run(seed):
    rnd=random.Random(seed); t=0; money=100; xp=0; lvl=1; owned=set(); log={}
    slots=3; bench=1
    while t<60*10 and len(owned)<len(UP):
        # per minute
        speed=1.0+0.15*sum(1 for u in owned if u[:-1] in('Brush','Polisher'))
        items_per_min=1.4*speed*bench* (1 if bench==1 else 0.8)  # 2nd bench only partly used solo? assume player alternates -> 0.8
        items_per_min=1.4*speed  # solo player: one pair of hands; bench2 only matters for co-op
        crate='Flea' if lvl>=5 and money>=300 else 'Starter'
        price,T,o,_=CR[crate]
        n=items_per_min
        # sell constraint
        interval=30*(0.9**sum(1 for u in owned if u.startswith('Sign')))
        sells=min(n,60/interval*1.0)
        quick=n-sells
        val=0;xpg=0
        for k in range(100):
            r=rnd.choices(R,o)[0]; v=rnd.choice(T[r])*1.2*(3 if rnd.random()<.02 else 1); val+=v; xpg+=XPR[r]*(1 if crate=='Starter' else 2)
        avgv=val/100; avgx=xpg/100
        money+= sells*avgv*1.15 + quick*avgv*0.7 - n*price/3
        xp+=n*avgx; t+=1
        while xp>=xpneed(lvl): xp-=xpneed(lvl); lvl+=1; money+=50*lvl; log.setdefault('Lv'+str(lvl),t)
        for name,cost,req in UP:
            if name not in owned and lvl>=req and money>=cost and (name not in REQ or REQ[name] in owned):
                money-=cost; owned.add(name); log[name]=t; break
    return log
logs=[run(s) for s in range(200)]
keys=['Lv5','Lv10','Lv12','Lv15','Lv20','Shelf1','Brush1','BackRoom','Neon','Brush2','Shelf3','Showroom','Sign3']
for k in keys:
    v=[l[k] for l in logs if k in l]
    if v: print(k,'median min',statistics.median(v),'n',len(v))
