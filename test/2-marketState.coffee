Promise = require 'bluebird'
Futu = require('../index').default

try
  futu = await new Futu()

  futu.subscribe (x) -> console.log JSON.stringify x
  await futu.marketState
    market: 'hk'
    code: '01211'
catch err
    console.error err
