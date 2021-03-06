module CleanDung

using DataFrames, CSV, ProgressMeter

export getdata

const factor_filename = "factors.csv"

# utility functions 
isnothidden(x) = x[1] ≠ '.'
isgooddir(root, x) = isdir(joinpath(root, x)) && isnothidden(x)
isgoodfile(root, x) = isfile(joinpath(root, x)) && isnothidden(x)
absfolders(dir) = filter(isdir, [joinpath(abspath(dir), d) for d in readdir(dir) if isnothidden(d)])
function makenextrun(dir) 
    nextrun = joinpath(dir, string(length(absfolders(dir)) + 1))
    mkdir(nextrun)
    nextrun
end

function my_mktempdir()
    dir = tempname()
    while isdir(dir)
        dir = tempname()
    end
    mkdir(dir)
end

# absreaddir(dir) = joinpath.(abspath(dir), readdir(dir))
# nohiddens(path) = all(d[1] ≠ '.' for d in split(path, '/') if !isempty(d)) # replace with splitpath in Julia v1.1

# core fcuntions 

function getsetup(experiment)
    fls = Dict{String, String}()
    for fl in split(experiment, ' ')
        f, l = split(fl, '#')
        fls[f] = l
    end
    fls
end

function getfl(dir, fl₀)
    fl = copy(fl₀)
    x = CSV.File(joinpath(dir, factor_filename), header=["factor", "level"], types=[String, Union{String, Missing}]) |> CSV.transform(factor = strip, level = x -> ismissing(x) ? missing : strip(x)) |> DataFrame
    dropmissing!(x)
    @assert allunique(x[:factor]) "factors not unique in $dir"
    for r in eachrow(x)
        if haskey(fl, r[:factor])
            key = r[:factor]
            oldv = fl[key]
            newv = r[:level]
            @warn "overwriting $key:$oldv with $newv in $dir"
        end
        fl[r[:factor]] = r[:level]
    end
    fl
end

function getfiles(dir)
    files = String[]
    for file in readdir(dir)
        if isgoodfile(dir, file) && file ≠ "factors.csv"
            push!(files, file)
        end
    end
    files
end

function copy2local(path, datadir)
    @showprogress  1 "fetching all the experiments…" for experiment in readdir(path)
        if isgooddir(path, experiment)
            FL = getsetup(experiment)
            pathexp = joinpath(path, experiment)
            for r in readdir(pathexp)
                if isgooddir(pathexp, r)
                    pathrun = joinpath(pathexp, r)
                    fl = getfl(pathrun, FL)
                    files = getfiles(pathrun)
                    nextrun = makenextrun(datadir)
                    writedlm(joinpath(nextrun, "factors.csv"), fl, ',')
                    for file in files
                        cp(joinpath(pathrun, file), joinpath(nextrun, file), force = true)
                    end
                end
            end
        end
    end
    @info "all the data is now in $datadir"
end

macro tryagain(ex)
    quote
        for i in 1:5
            try 
                $(esc(ex))
                break
            catch except
                @warn "failed! trying $(5-i) more times"
                if i < 5
                    sleep(1)
                    continue
                else
                    throw(except)
                end
            end
        end
    end
end

function getdata(;clean_cash = false)
    datadir = my_mktempdir()
    path = my_mktempdir()
    gdfuse_config = joinpath(@__DIR__, "gdfuse_config")
    run(`google-drive-ocamlfuse -config $gdfuse_config $path`)
    @tryagain copy2local(path, datadir)
    cmd = `fusermount -zu $path`
    @tryagain run(cmd)
    clean_cash && @tryagain run(`google-drive-ocamlfuse -cc`)
    rm(path)
    datadir
end

end # module
