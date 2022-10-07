local skynet = require "skynet"
local s = require "service"
local socket = require "skynet.socket"
local runconfig = require "runconfig"

local conns = {}    -- [fd] = conn
local players = {}  -- [playerid] = gateplayer

-- 连接类
function conn()
    local m = {
        fd = nil,
        playerid = nil,
    }

    return m
end

-- 玩家类
function gateplayer()
    local m = {
        playerid = nil,
        agent = nil,
        conn = nil,
    }

    return m
end

-- 字符串消息解码
local str_unpack = function (msgstr)
    local msg = {}

    while true do
        local arg, rest = string.match(msgstr, "(.-),(.*)")
        if arg then
            msgstr = rest
            table.insert(msg, arg)
        else
            table.insert(msg, msgstr)
            break
        end
    end

    return msg[1], msg
end

-- 字符串消息编码
local str_pack = function (cmd, msg)
    return table.concat(msg, ',')..'\r\n'
end

---解析消息命令
---@param fd any
---@param msgstr any
local process_msg = function(fd, msgstr)
    local cmd, msg = str_unpack(msgstr)
    skynet.error("recv fd "..fd..":["..cmd.."]{"..table.concat(msg, ",").."}")

    local conn = conns[fd]
    local playerid = conn.playerid

    -- 尚未完成登录流程，要把消息发给随机选取的一个login服务进行登录验证
    if not playerid then
        -- skynet.error("User (fd is "..fd..") has not logined.")
        local node = skynet.getenv("node")
        local nodecfg = runconfig[node]
        local loginid = math.random(1, #nodecfg.login)
        local login = "login"..loginid
        skynet.send(login, "lua", "client", fd, cmd, msg)
    -- 已完成登录流程，则把消息发给客户端对应的agent进行消息处理
    else
        -- skynet.error("User"..playerid.."has logined.")
        local gplayer = players[playerid]
        local agent = gplayer.agent
        skynet.send(agent, "lua", "client", cmd, msg)
    end
end

---解析客户端消息
---@param fd any
---@param readbuff any
---@return any
local process_buff = function(fd, readbuff)
    while true do
        local msgstr, rest = string.match(readbuff, "(.-)\r\n(.*)")
        if msgstr then
            readbuff = rest
            process_msg(fd, msgstr)
        else
            return readbuff
        end
    end
end

---玩家断线后的处理流程
---@param fd any
local disconnect = function(fd)
    local c = conns[fd]
    if not c then
        return
    end

    conns[fd] = nil

    local playerid = c.playerid
    -- 还没完成登录
    if not playerid then
        return
    -- 已在游戏中
    else
        players[playerid] = nil
        local reason = "断线"
        skynet.call("agentmgr", "lua", "reqkick", playerid, reason)
    end
    
end

-- 每一条连接接收数据处理
local recv_loop = function(fd)
    socket.start(fd)
    skynet.error("socket connected fd:"..fd)
    local readbuff = ""

    while true do
        local recvstr = socket.read(fd)
        if recvstr then
            readbuff = readbuff..recvstr
            readbuff = process_buff(fd, readbuff)
        else
            skynet.error("socket close fd:"..fd)
            disconnect(fd)
            socket.close(fd)
            return
        end
    end
end

local connect = function(fd, addr)
    skynet.error("connected from " .. addr .. " fd:" .. fd)
    local c = conn()
    conns[fd] = c
    c.fd = fd
    skynet.fork(recv_loop, fd)
end

---转发login服务的消息给客户端
---@param source any
---@param fd any
---@param msg any
s.resp.send_by_fd = function (source, fd, msg)
    if not conns[fd] then
        return
    end

    local buff = str_pack(msg[1], msg)
    skynet.error("send fd "..fd..":["..msg[1].."]{"..table.concat(msg, ",").."}")
    socket.write(fd, buff)
end

---转发agent的消息给客户端
---@param source any
---@param playerid any
---@param msg any
s.resp.send = function (source, playerid, msg)
    local gplayer = players[playerid]
    if not gplayer then
        return
    end

    local c = gplayer.conn
    if not c then
        return
    end

    s.resp.send_by_fd(nil, c.fd, msg)
end


---接收确认客户端登录成功的结果
---@param source any
---@param fd any
---@param playerid any
---@param agent any
---@return boolean
s.resp.sure_agent = function(source, fd, playerid, agent)
    local conn = conns[fd]
    if not conn then
        skynet.call("agentmgr", "lua", "reqkick", playerid, "未完成登录即下线")
        return false
    end

    conn.playerid = playerid

    local gplayer = gateplayer()
    gplayer.playerid = playerid
    gplayer.agent = agent
    gplayer.conn = conn
    players[playerid] = gplayer

    return true
end

---接收agentmgr主动踢出玩家的调用
---@param source any
---@param playerid any
s.resp.kick = function (source, playerid)
    local gplayer = players[playerid]
    if not gplayer then
        return
    end

    players[playerid] = nil

    local c = gplayer.conn
    if not c then
        return
    end

    conns[c.fd] = nil
    disconnect(c.fd)
    socket.close(c.fd)
end

---初始化开启网关监听
function s.init()
    skynet.error("...开启网关监听...")
    local node = skynet.getenv("node")
    local nodecfg = runconfig[node]
    local port = nodecfg.gateway[s.id].port

    local listenfd = socket.listen("0.0.0.0", port)
    skynet.error("listen socket:", "0.0.0.0", port)
    socket.start(listenfd, connect)
end

s.start(...)