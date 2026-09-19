local function connect(host)
  return { host = host or "127.0.0.1", port = 8080 }
end

return {
  connect = connect,
}
