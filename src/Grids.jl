
## GridSpec function with default GridName argument:

GridSpec() = GridSpec("LLC90")

## GridSpec function with GridName argument:

"""
    GridSpec(GridName)

Return a `gmcgrid` specification that provides grid files `path`,
`class`, `nFaces`, `ioSize`, `facesSize`, `ioPrec`, & a `read` function
(not yet) using hard-coded values for `"LLC90"`, `"CS32"`, `"LL360"` (for now).
"""
function GridSpec(GridName,GridParentDir="./")

if GridName=="LLC90";
    grDir=GridParentDir*"GRID_LLC90/";
    nFaces=5;
    grTopo="llc";
    ioSize=[90 1170];
    facesSize=[(90, 270), (90, 270), (90, 90), (270, 90), (270, 90)]
    ioPrec=Float64;
elseif GridName=="CS32";
    grDir=GridParentDir*"GRID_CS32/";
    nFaces=6;
    grTopo="cs";
    ioSize=[32 192];
    facesSize=[(32, 32), (32, 32), (32, 32), (32, 32), (32, 32), (32, 32)]
    ioPrec=Float32;
elseif GridName=="LL360";
    grDir=GridParentDir*"GRID_LL360/";
    nFaces=1;
    grTopo="ll";
    ioSize=[360 160];
    facesSize=[(360, 160)]
    ioPrec=Float32;
elseif GridName=="FLTXMPL";
    grDir=GridParentDir*"flt_example/";
    nFaces=4;
    grTopo="dpdo";
    ioSize=[80 42];
    facesSize=[(40, 21), (40, 21), (40, 21), (40, 21)]
    ioPrec=Float32;
else;
    error("unknown GridName case");
end;

mygrid=gcmgrid(grDir,grTopo,nFaces,facesSize, ioSize, ioPrec, read, write)

return mygrid

end

## GridLoad function

"""
    GridLoad(mygrid::gcmgrid)

Return a `Dict` of grid variables read from files located in `mygrid.path` (see `?GridSpec`).

Based on the MITgcm naming convention, grid variables are:

- XC, XG, YC, YG, AngleCS, AngleSN, hFacC, hFacS, hFacW, Depth.
- RAC, RAW, RAS, RAZ, DXC, DXG, DYC, DYG.
- DRC, DRF, RC, RF (one-dimensional)
"""
function GridLoad(mygrid::gcmgrid)

    GridVariables=Dict()

    list0=("XC","XG","YC","YG","AngleCS","AngleSN","RAC","RAW","RAS","RAZ",
    "DXC","DXG","DYC","DYG","Depth")
    for ii=1:length(list0)
        tmp1=mygrid.read(mygrid.path*list0[ii]*".data",MeshArray(mygrid,mygrid.ioPrec))
        tmp2=Symbol(list0[ii])
        @eval (($tmp2) = ($tmp1))
        GridVariables[list0[ii]]=tmp1
    end

    mygrid.ioPrec==Float64 ? reclen=8 : reclen=4

    list0=("DRC","DRF","RC","RF")
    for ii=1:length(list0)
        fil=mygrid.path*list0[ii]*".data"
        tmp1=stat(fil)
        n3=Int64(tmp1.size/reclen)

        fid = open(fil)
        tmp1 = Array{mygrid.ioPrec,1}(undef,n3)
        read!(fid,tmp1)
        tmp1 = hton.(tmp1)

        tmp2=Symbol(list0[ii])
        @eval (($tmp2) = ($tmp1))
        GridVariables[list0[ii]]=tmp1
    end

    list0=("hFacC","hFacS","hFacW")
    n3=length(GridVariables["RC"])
    for ii=1:length(list0)
        tmp1=mygrid.read(mygrid.path*list0[ii]*".data",MeshArray(mygrid,mygrid.ioPrec,n3))
        tmp2=Symbol(list0[ii])
        @eval (($tmp2) = ($tmp1))
        GridVariables[list0[ii]]=tmp1
    end

    return GridVariables

end

"""
    GridOfOnes(grTp,nF,nP)

Define all-ones grid variables instead of using `GridSpec` & `GridLoad`.
"""
function GridOfOnes(grTp,nF,nP)

    grDir=""
    grTopo=grTp
    nFaces=nF
    if grTopo=="llc"
        ioSize=[nP nP*nF]
    elseif grTopo=="cs"
        ioSize=[nP nP*nF]
    elseif grTopo=="ll"
        ioSize=[nP nP]
    elseif grTopo=="dpdo"
        nFsqrt=Int(sqrt(nF))
        ioSize=[nP*nFsqrt nP*nFsqrt]
    end
    facesSize=Array{NTuple{2, Int},1}(undef,nFaces)
    facesSize[:].=[(nP,nP)]
    ioPrec=Float32

    mygrid=gcmgrid(grDir,grTopo,nFaces,facesSize, ioSize, ioPrec, read, write)

    GridVariables=Dict()
    list0=("XC","XG","YC","YG","RAC","RAZ","DXC","DXG","DYC","DYG","hFacC","hFacS","hFacW","Depth");
    for ii=1:length(list0);
        tmp1=fill(1.,nP,nP*nF);
        tmp1=mygrid.read(tmp1,MeshArray(mygrid,Float64));
        tmp2=Symbol(list0[ii]);
        @eval (($tmp2) = ($tmp1))
        GridVariables[list0[ii]]=tmp1
    end

    return GridVariables

end

"""
    TileMap(ni::Int,nj::Int,mygrid::gcmgrid)

Return a `MeshArray` map of tile indices for tile size `ni,nj`
"""
function TileMap(mygrid::gcmgrid,ni::Int,nj::Int)
    nbr=MeshArray(mygrid)
    #
    cnt=0
    for iF=1:mygrid.nFaces
        for jj=Int.(1:mygrid.fSize[iF][2]/nj)
            for ii=Int.(1:mygrid.fSize[iF][1]/ni)
                cnt=cnt+1
                tmp_i=(1:ni).+ni*(ii-1)
                tmp_j=(1:nj).+nj*(jj-1)
                nbr.f[iF][tmp_i,tmp_j]=cnt*ones(Int,ni,nj)
            end
        end
    end
    #
    return nbr
end

"""
    findtiles(ni::Int,nj::Int,mygrid::gcmgrid)
    findtiles(ni::Int,nj::Int,grid::String="llc90",GridParentDir="./")

Return a `MeshArray` map of tile indices, `mytiles["tileNo"]`, for tile
size `ni,nj` and extract grid variables accordingly.
"""
function findtiles(ni::Int,nj::Int,mygrid::gcmgrid)
    mytiles = Dict()

    GridVariables=GridLoad(mygrid)

    mytiles["nFaces"]=mygrid.nFaces;
    mytiles["ioSize"]=mygrid.ioSize;

    XC=GridVariables["XC"];
    YC=GridVariables["YC"];
    XC11=similar(XC); YC11=similar(XC);
    XCNINJ=similar(XC); YCNINJ=similar(XC);
    iTile=similar(XC); jTile=similar(XC); tileNo=similar(XC);
    tileCount=0;
    for iF=1:XC11.grid.nFaces
        face_XC=XC.f[iF]; face_YC=YC.f[iF];
        for jj=Int.(1:size(face_XC,2)/nj);
            for ii=Int.(1:size(face_XC,1)/ni);
                tileCount=tileCount+1;
                tmp_i=(1:ni).+ni*(ii-1)
                tmp_j=(1:nj).+nj*(jj-1)
                tmp_XC=face_XC[tmp_i,tmp_j]
                tmp_YC=face_YC[tmp_i,tmp_j]
                XC11.f[iF][tmp_i,tmp_j].=tmp_XC[1,1]
                YC11.f[iF][tmp_i,tmp_j].=tmp_YC[1,1]
                XCNINJ.f[iF][tmp_i,tmp_j].=tmp_XC[end,end]
                YCNINJ.f[iF][tmp_i,tmp_j].=tmp_YC[end,end]
                iTile.f[iF][tmp_i,tmp_j]=collect(1:ni)*ones(Int,1,nj)
                jTile.f[iF][tmp_i,tmp_j]=ones(Int,ni,1)*collect(1:nj)'
                tileNo.f[iF][tmp_i,tmp_j]=tileCount*ones(Int,ni,nj)
            end
        end
    end

    mytiles["tileNo"] = tileNo;
    mytiles["XC"] = XC;
    mytiles["YC"] = YC;
    mytiles["XC11"] = XC11;
    mytiles["YC11"] = YC11;
    mytiles["XCNINJ"] = XCNINJ;
    mytiles["YCNINJ"] = YCNINJ;
    mytiles["iTile"] = iTile;
    mytiles["jTile"] = jTile;

    return mytiles

end

findtiles(ni::Int,nj::Int,GridName::String="llc90",GridParentDir="./") = findtiles(ni,nj,GridSpec(GridName,GridParentDir))


"""
    GridAddWS!(GridVariables::Dict)

Compute XW, YW, XS, and YS (vector field locations) from XC, YC (tracer
field locations) and add them to GridVariables.

```
GridVariables=GridLoad(GridSpec("LLC90"))
GridAddWS!(GridVariables)
```
"""
function GridAddWS!(GridVariables::Dict)

    XC=exchange(GridVariables["XC"])
    YC=exchange(GridVariables["YC"])
    nFaces=XC.grid.nFaces
    XW=NaN .* XC; YW=NaN .* YC; XS=NaN .* XC; YS=NaN .* YC;

    for ff=1:nFaces
        tmp1=XC[ff][1:end-2,2:end-1]
        tmp2=XC[ff][2:end-1,2:end-1]
        tmp2[tmp2.-tmp1.>180]=tmp2[tmp2.-tmp1.>180].-360;
        tmp2[tmp1.-tmp2.>180]=tmp2[tmp1.-tmp2.>180].+360;
        XW[ff]=(tmp1.+tmp2)./2;
       #
        tmp1=XC[ff][2:end-1,1:end-2]
        tmp2=XC[ff][2:end-1,2:end-1]
        tmp2[tmp2.-tmp1.>180]=tmp2[tmp2.-tmp1.>180].-360;
        tmp2[tmp1.-tmp2.>180]=tmp2[tmp1.-tmp2.>180].+360;
        XS[ff]=(tmp1.+tmp2)./2;
       #
        tmp1=YC[ff][1:end-2,2:end-1]
        tmp2=YC[ff][2:end-1,2:end-1]
        YW[ff]=(tmp1.+tmp2)./2;
       #
        tmp1=YC[ff][2:end-1,1:end-2]
        tmp2=YC[ff][2:end-1,2:end-1]
        YS[ff]=(tmp1.+tmp2)./2;
    end;

    Xmax=180; Xmin=-180;
    XS[findall(XS.<Xmin)]=XS[findall(XS.<Xmin)].+360;
    XS[findall(XS.>Xmax)]=XS[findall(XS.>Xmax)].-360;
    XW[findall(XW.<Xmin)]=XW[findall(XW.<Xmin)].+360;
    XW[findall(XW.>Xmax)]=XW[findall(XW.>Xmax)].-360;

    GridVariables["XW"]=XW
    GridVariables["XS"]=XS
    GridVariables["YW"]=YW
    GridVariables["YS"]=YS
    return GridVariables
end
