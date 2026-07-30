#!/usr/bin/env python3
"""Independent reference ballistics solver to cross-check the Dart engine.

Implements the same 3D RK4 model: drag (G1, form-factor scaled), gravity,
wind via relative velocity. Verifies drop / windage against published values
for a 168gr .308 SMK (G1 BC=0.462, MV=2600fps), 200yd zero, 1.5" sight.
"""
import math

# G1 reference drag table (Mach, Cd)
G1 = [
    (0.00,0.2629),(0.50,0.2032),(0.55,0.2020),(0.60,0.2034),(0.65,0.2165),
    (0.70,0.2290),(0.75,0.2518),(0.80,0.3011),(0.85,0.4005),(0.90,0.5149),
    (0.95,0.5718),(1.00,0.4790),(1.05,0.4050),(1.10,0.3497),(1.15,0.3148),
    (1.20,0.2922),(1.30,0.2684),(1.40,0.2560),(1.50,0.2483),(1.60,0.2431),
    (1.75,0.2378),(2.00,0.2324),(2.50,0.2260),(3.00,0.2218),(4.00,0.2152),(5.00,0.2100),
]

def cd_ref(mach):
    if mach <= G1[0][0]: return G1[0][1]
    if mach >= G1[-1][0]: return G1[-1][1]
    for i in range(len(G1)-1):
        x0,y0 = G1[i]; x1,y1 = G1[i+1]
        if x0 <= mach <= x1:
            f = (mach-x0)/(x1-x0)
            return y0 + f*(y1-y0)
    return G1[-1][1]

GRAIN_LB = 1/7000.0
IN_M = 0.0254
FT_M = 0.3048
YD_M = 0.9144

def sectional_density(mass_gr, dia_in):
    return (mass_gr*GRAIN_LB)/(dia_in*dia_in)

def solve(mv_fps, bc, mass_gr, dia_in, sight_in, zero_yd, wind_mph=None, wind_dir=None,
          max_yd=800, step_yd=50, dt=1e-4):
    mv = mv_fps*FT_M
    mass = mass_gr*GRAIN_LB*0.45359237
    dia = dia_in*IN_M
    sight = sight_in*IN_M
    zero = zero_yd*YD_M
    area = math.pi*dia*dia/4.0
    sd = sectional_density(mass_gr, dia_in)
    form = sd/bc
    # atmosphere
    rho = 1.225
    cs = 340.3
    g = 9.80665
    # wind vector
    wvx = wvy = 0.0
    if wind_mph:
        wm = wind_mph*0.44704
        r = math.radians(wind_dir or 0)
        wvx = -wm*math.cos(r); wvy = -wm*math.sin(r)

    def accel(x,y,z,vx,vy,vz):
        vrx = vx-wvx; vry = vy-wvy; vrz = vz
        vr = math.sqrt(vrx*vrx+vry*vry+vrz*vrz) or 1e-9
        mach = vr/cs
        cd = cd_ref(mach)*form
        dm = rho*cd*area*vr*vr/(2*mass)
        ax = -dm*vrx/vr
        ay = -dm*vry/vr
        az = -dm*vrz/vr - g
        return ax,ay,az

    def integrate(elev, stop):
        x=y=0.0; z=-sight
        vx=mv*math.cos(elev); vy=0.0; vz=mv*math.sin(elev)
        t=0.0
        while x < stop and z > -1000:
            ax,ay,az = accel(x,y,z,vx,vy,vz)
            k1px,k1py,k1pz=vx,vy,vz; k1ax,k1ay,k1az=ax,ay,az
            ax2,ay2,az2 = accel(x+0.5*dt*k1px,y+0.5*dt*k1py,z+0.5*dt*k1pz,
                                vx+0.5*dt*k1ax,vy+0.5*dt*k1ay,vz+0.5*dt*k1az)
            k2px=vx+0.5*dt*k1ax;k2py=vy+0.5*dt*k1ay;k2pz=vz+0.5*dt*k1az
            ax3,ay3,az3 = accel(x+0.5*dt*k2px,y+0.5*dt*k2py,z+0.5*dt*k2pz,
                                vx+0.5*dt*ax2,vy+0.5*dt*ay2,vz+0.5*dt*az2)
            k3px=vx+0.5*dt*ax2;k3py=vy+0.5*dt*ay2;k3pz=vz+0.5*dt*az2
            ax4,ay4,az4 = accel(x+dt*k3px,y+dt*k3py,z+dt*k3pz,
                                vx+dt*ax3,vy+dt*ay3,vz+dt*az3)
            six=1/6.0
            nx = x+dt*six*(k1px+2*k2px+2*k3px+(vx+dt*ax3))
            ny = y+dt*six*(k1py+2*k2py+2*k3py+(vy+dt*ay3))
            nz = z+dt*six*(k1pz+2*k2pz+2*k3pz+(vz+dt*az3))
            nvx = vx+dt*six*(k1ax+2*ax2+2*ax3+ax4)
            nvy = vy+dt*six*(k1ay+2*ay2+2*ay3+ay4)
            nvz = vz+dt*six*(k1az+2*az2+2*az3+az4)
            if nx <= x: break
            x,y,z,vx,vy,vz,t = nx,ny,nz,nvx,nvy,nvz,t+dt
        return x,y,z,vx,vy,vz

    # find zero elevation by bisection: want z(zero)=0
    lo,hi=-0.02,0.3
    def z_at(theta):
        _,_,zz,_,_,_ = integrate(theta, zero)
        return zz
    flo,fhi = z_at(lo),z_at(hi)
    for _ in range(80):
        if (flo>0)!=(fhi>0): break
        hi+=0.05; fhi=z_at(hi)
    for _ in range(80):
        mid=0.5*(lo+hi); fm=z_at(mid)
        if (flo>0)!=(fm>0): hi,fhi=mid,fm
        else: lo,flo=mid,fm
    elev=0.5*(lo+hi)

    # full trajectory sampling
    pts=[]
    nxt=0.0
    maxr=max_yd*YD_M
    # store full states in one pass for interpolation
    # re-integrate storing states
    states=[]
    x=y=0.0;z=-sight
    vx=mv*math.cos(elev);vy=0.0;vz=mv*math.sin(elev);t=0.0
    states.append((x,y,z,vx,vy,vz,t))
    while x<maxr and z>-1000:
        ax,ay,az = accel(x,y,z,vx,vy,vz)
        k1px,k1py,k1pz=vx,vy,vz;k1ax,k1ay,k1az=ax,ay,az
        ax2,ay2,az2 = accel(x+0.5*dt*k1px,y+0.5*dt*k1py,z+0.5*dt*k1pz,
                            vx+0.5*dt*k1ax,vy+0.5*dt*k1ay,vz+0.5*dt*k1az)
        k2px=vx+0.5*dt*k1ax;k2py=vy+0.5*dt*k1ay;k2pz=vz+0.5*dt*k1az
        ax3,ay3,az3 = accel(x+0.5*dt*k2px,y+0.5*dt*k2py,z+0.5*dt*k2pz,
                            vx+0.5*dt*ax2,vy+0.5*dt*ay2,vz+0.5*dt*az2)
        k3px=vx+0.5*dt*ax2;k3py=vy+0.5*dt*ay2;k3pz=vz+0.5*dt*az2
        ax4,ay4,az4 = accel(x+dt*k3px,y+dt*k3py,z+dt*k3pz,
                            vx+dt*ax3,vy+dt*ay3,vz+dt*az3)
        six=1/6.0
        x=x+dt*six*(k1px+2*k2px+2*k3px+(vx+dt*ax3))
        y=y+dt*six*(k1py+2*k2py+2*k3py+(vy+dt*ay3))
        z=z+dt*six*(k1pz+2*k2pz+2*k3pz+(vz+dt*az3))
        vx=vx+dt*six*(k1ax+2*ax2+2*ax3+ax4)
        vy=vy+dt*six*(k1ay+2*ay2+2*ay3+ay4)
        vz=vz+dt*six*(k1az+2*az2+2*az3+az4)
        t+=dt
        if x<=states[-1][0]: break
        states.append((x,y,z,vx,vy,vz,t))
    i=0
    while nxt<=maxr+1e-6:
        while i<len(states)-1 and states[i][0]<nxt: i+=1
        if i==0: i=1
        p0=states[i-1]; p1=states[i]
        spx=p1[0]-p0[0]
        f = (nxt-p0[0])/spx if abs(spx)>1e-9 else 0
        x=nxt
        y=p0[1]+f*(p1[1]-p0[1])
        z=p0[2]+f*(p1[2]-p0[2])
        vx=p0[3]+f*(p1[3]-p0[3]); vy=p0[4]+f*(p1[4]-p0[4]); vz=p0[5]+f*(p1[5]-p0[5])
        tof=p0[6]+f*(p1[6]-p0[6])
        spd=math.sqrt(vx*vx+vy*vy+vz*vz)
        pts.append((x,y,z,spd,tof))
        nxt+=step_yd*YD_M
    return elev, pts

if __name__=="__main__":
    print("=== 168gr .308 SMK, BC=0.462 G1, MV=2600fps, 200yd zero, 1.5in sight ===")
    elev, pts = solve(2600,0.462,168,0.308,1.5,200, max_yd=600, step_yd=100)
    print(f"zero elevation = {math.degrees(elev):.3f} deg")
    print(f"{'yd':>5} {'drop_cm':>9} {'drop_in':>9} {'wind_cm':>8} {'vel_mps':>8} {'vel_fps':>8} {'tof_s':>7}")
    for x,y,z,spd,tof in pts:
        yd = x/YD_M
        print(f"{yd:5.0f} {z*100:9.1f} {z/IN_M:9.1f} {y*100:8.2f} {spd:8.1f} {spd/FT_M:8.0f} {tof:7.3f}")
    print()
    print("=== with 10mph wind from the left (270deg) ===")
    _, pts2 = solve(2600,0.462,168,0.308,1.5,200, wind_mph=10, wind_dir=270, max_yd=500, step_yd=100)
    for x,y,z,spd,tof in pts2:
        yd=x/YD_M
        print(f"{yd:5.0f}  windage={y/IN_M:6.1f} in ({y*100:5.1f} cm)")
