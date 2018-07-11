# state transition:
#   initialized => inprogress => finished => finalized

@compat primitive type State 8 end

const initialized = reinterpret(State, 0x00)
const inprogress  = reinterpret(State, 0x01)
const finished    = reinterpret(State, 0x02)
const finalized   = reinterpret(State, 0x03)
# const errored?

function Base.show(io::IO, s::State)
    if s == initialized
        print(io, "initialized")
    elseif s == inprogress
        print(io, "inprogress")
    elseif s == finished
        print(io, "finished")
    elseif s == finalized
        print(io, "finalized")
    else
        @assert false
    end
end

# do state transition
if VERSION < v"0.6.0-dev.2577" # after which `A=>B` is parsed as a `call`
    macro trans(obj, ts)
        if ts.head == :(=>)
            ts = :($(ts),)
        end
        @assert ts.head == :tuple
        foldr(:(error("invalid state: ", $(esc(obj)).state)), ts.args) do t, elblk
            @assert t.head == :(=>)
            from, to = t.args
            quote
                if $(esc(obj)).state == $(esc(from))
                    $(esc(obj)).state = $(esc(to))
                else
                    $(elblk)
                end
            end
        end
    end
else
    macro trans(obj, ts)
        if ts.head == :call && ts.args[1] == :(=>)
            ts = :($(ts),)
        end
        @assert ts.head == :tuple
        if VERSION < v"0.7.0-beta.66" # changed calling convention for foldr
            foldr(:(error("invalid state: ", $(esc(obj)).state)), ts.args) do t, elblk
                @assert t.head == :call && t.args[1] == :(=>)
                from, to = t.args[2], t.args[3]
                quote
                    if $(esc(obj)).state == $(esc(from))
                        $(esc(obj)).state = $(esc(to))
                    else
                        $(elblk)
                    end
                end
            end
        else
            foldr(ts.args, init = :(error("invalid state: ", $(esc(obj)).state))) do t, elblk
                @assert t.head == :call && t.args[1] == :(=>)
                from, to = t.args[2], t.args[3]
                quote
                    if $(esc(obj)).state == $(esc(from))
                        $(esc(obj)).state = $(esc(to))
                    else
                        $(elblk)
                    end
                end
            end
        end
    end
end
