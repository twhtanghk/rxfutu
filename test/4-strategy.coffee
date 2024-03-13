_ = require 'lodash'
moment = require 'moment'
Futu = require('../index').default
strategy = require('algotrader/rxStrategy').default
{skipDup} = require('algotrader/analysis').default.ohlc
import {EMPTY, switchMap, tap, map, filter} from 'rxjs'

enable = false
process.on 'SIGUSR1', ->
  enable = !enable
  console.log "enable = #{enable}"

if process.argv.length != 5
  console.log 'node -r coffeescript/register -r esm test/strategy code, optCode, meanReversion'
  process.exit 1

position = ({broker, market, code}) ->
  found = (await (await broker.defaultAcc()).position())
  found = found
    .find (i) ->
      code == i.code
  if found?
    _.pick found, [
      'code'
      'name'
      'qty'
      'canSellQty'
      'price'
      'costPrice'
      'plVal'
      'plRation'
    ]
  else
    code: code
    qty: 0
    canSellQty: 0

decision = ({entry, opt}) ->
  if entry == 'buy'
    if opt == 'call'
      'longCall'
    else if opt == 'put'
      'shortPut'
  else if entry == 'sell'
    if opt == 'call'
      'shortCall'
    else if opt = 'put'
      'longPut'

do ->
  try 
    [..., code, optCode, selectedStrategy] = process.argv
    market = 'hk'
    freq = '5'
    broker = await new Futu()
    account = await broker.defaultAcc()
    opts =
      market: market
      code: code
      start: moment().subtract minute: 60 * parseInt freq
      freq: freq
    (await broker.dataKL opts)
      .pipe filter (i) ->
        market == i.market and code == i.code and freq == i.freq
      .pipe skipDup 'timestamp'
      .pipe map (i) ->
        i.date = new Date i.timestamp * 1000
        i
      .pipe strategy.indicator()
      .pipe strategy[selectedStrategy]()
      .pipe strategy.volUp()
      .pipe filter (i) ->
        'entryExit' of i
      # check position and active order
      .pipe switchMap (i) ->
        {side} = Futu.optCode optCode
        {canSellQty} = await position 
          broker: broker
          market: market
          code: optCode
        switch decision {entry: i.entryExit.side, opt: side}
          when 'longCall'
            if canSellQty > 0 then EMPTY else i
          when 'shortCall'
            if canSellQty < 0 then EMPTY else i
          when 'longPut'
            if canSellQty > 0 then EMPTY else i
          when 'shortPut'
            if canSellQty < 0 then EMPTY else i
      .pipe tap console.log
      .pipe filter ->
        enable
      .subscribe (i) ->
        position = await account.position()
        {open, close} = i
        price = (await broker.quickQuote({market, code}))[i.entryExit.side]
        params =
          code: opts.code
          side: i.entryExit.side
          type: 'limit'
          price: price
        try
          if i.entryExit.side == 'buy' and position.USDT? and position.USDT > 10
            params.qty = Math.floor(position.USDT * 1000 / price) / 1000
            console.log params
            index = await account.placeOrder params
            await account.enableOrder index
          if i.entryExit.side == 'sell' and position.ETH? and position.ETH > 0.01
            params.qty = Math.floor(position.ETH * 1000) / 1000
            console.log params
            index = await account.placeOrder params
            await account.enableOrder index
        catch err
          console.error err
  catch err
    console.error err
