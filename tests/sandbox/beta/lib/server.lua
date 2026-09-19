local function listen(port)
  return { port = port or 8080, status = "idle" }
end

return {
  listen = listen,
}
