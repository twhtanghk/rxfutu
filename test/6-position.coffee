Futu = require '../index'

try 
  broker = await new Futu()
  console.log await (await broker.defaultAcc()).position()
catch e
  console.error e
