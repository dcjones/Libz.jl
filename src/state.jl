# state transition:
#   initialized => inprogress => finished => finalized

bitstype 8 State

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
macro trans(obj, ts)
    if ts.head == :(=>)
        ts = :($(ts),)
    end
    @assert ts.head == :tuple
    foldr(:(error("invalid state: ", $(obj).state)), ts.args) do t, elblk
        @assert t.head == :(=>)
        from, to = t.args
        quote
            if $(obj).state == $(from)
                $(obj).state = $(to)
            else
                $(elblk)
            end
        end
    end
end
