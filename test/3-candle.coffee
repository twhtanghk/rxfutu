Promise = require 'bluebird'
moment = require 'moment'
Futu = require('../index').default

try
  futu = await new Futu()

  (await futu
    .dataKL
      market: 'hk'
      code: '01211'
      start: moment().subtract week: 1
      freq: '1')
    .subscribe (x) -> console.log JSON.stringify x
  Promise
    .delay 60000
    .then ->
      await futu.unsubKL
        market: 'hk'
        code: '01211'
        freq: '1'
catch err
    console.error err
