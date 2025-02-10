Promise = require 'bluebird'
moment = require 'moment'
Futu = require '../index'
ta = require 'talib'
{reduce, map, tap} = require 'rxjs'

try
  func = (name for {name} in ta.functions)
  console.log func.filter (name) ->
    name.match '^CDL'

  do ->
    futu = await new Futu()
    acc = (ret, i) ->
      ret.push i
      ret
    kl = (await futu
      .historyKL
        market: 'hk'
        code: '01211'
        start: moment().subtract day: 1
        end: moment()
        freq: '1'
      )
      .pipe map (x) ->
        x.timestamp = new Date x.timestamp * 1000
        x
      .pipe tap console.log
      .pipe reduce acc, []
      .subscribe (x) ->
        ta.execute {
          name: 'CDLHAMMER'
          startIdx: 0
          endIdx: x.length - 1
          open: x.map ({open}) -> open
          high: x.map ({high}) -> high
          low: x.map ({low}) -> low
          close: x.map ({close}) -> close
        }, (err, {result}) ->
          result.outInteger.map (value, i) ->
            {close, timestamp} = x[i + 11]
            console.log {value, close, timestamp}
catch err
    console.error err
