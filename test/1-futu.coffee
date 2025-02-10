Promise = require 'bluebird'
Futu = require '../index'

try
  futu = await new Futu()

  futu.subscribe (x) -> console.log JSON.stringify x
  await futu.basicQuote
    market: 'hk'
    code: '01211'
catch err
  console.error err
