moment = require 'moment'
Futu = require('../index').default

try
  futu = await new Futu()

  futu
    .dataKL
      market: 'hk'
      code: '01211'
      start: moment().subtract week: 1
      freq: '1'
    .subscribe (x) -> console.log JSON.stringify x
catch err
    console.error err
