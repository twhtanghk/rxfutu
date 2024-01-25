Promise = require 'bluebird'
Futu = require('../index').default

futu = await new Futu()

do ->
  try
    await futu.basicQuote
      market: 'hk'
      code: '01211'
    futu.subscribe (x) -> console.log JSON.stringify x
  catch err
    console.error err
