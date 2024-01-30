_ = require 'lodash'
moment = require 'moment'
Promise = require 'bluebird'
import {from, filter, map} from 'rxjs'
{Broker} = AlgoTrader = require('algotrader/rxData').default
import ftWebsocket from 'futu-api'
import { ftCmdID } from 'futu-api'
import {Common, Qot_Common, Trd_Common} from 'futu-api/proto'
{TradeDateMarket, SubType, RehabType, KLType, QotMarket} = Qot_Common
{RetType} = Common
{ModifyOrderOp, OrderType, OrderStatus, SecurityFirm, TrdEnv, TrdMarket, TrdSecMarket, TrdSide, TimeInForce} = Trd_Common

class Account extends AlgoTrader.Account
  constructor: (opts) ->
    super()
    {broker, trdEnv, accID, trdMarketAuthList, accType, cardNum, securityFirm} = opts
    @broker = broker
    @id = accID
    @trdEnv = trdEnv
    @market = trdMarketAuthList
    @type = accType
    @cardNum = cardNum
    @securityFirm = securityFirm

  position: ->
    req =
      c2s:
        header:
          trdEnv: @trdEnv
          accID: @id
          trdMarket: @market[0]
    (Futu.errHandler await @broker.ws.GetPositionList req).positionList

class Futu extends Broker
  @marketMap:
    'hk': QotMarket.QotMarket_HK_Security
    'us': QotMarket.QotMarket_US_Securityx

  @subTypeMap:
    'Basic': SubType.SubType_Basic
    'Broker': SubType.SubType_Broker
    '1': SubType.SubType_KL_1Min
    '5': SubType.SubType_KL_5Min
    '15': SubType.SubType_KL_15Min
    '30': SubType.SubType_KL_30Min
    '1h': SubType.SubType_KL_60Min
    '1d': SubType.SubType_KL_Day
    '1w': SubType.SubType_KL_Week
    '1m': SubType.SubType_KL_Month
    '3m': SubType.SubType_KL_Quarter
    '1y': SubType.SubType_KL_Year

  @freqMap: Futu.subTypeMap

  @klTypeMap:
    '1': KLType.KLType_1Min
    '5': KLType.KLType_5Min
    '15': KLType.KLType_15Min
    '30': KLType.KLType_30Min
    '1h': KLType.KLType_60Min
    '1d': KLType.KLType_Day
    '1w': KLType.KLType_Week
    '1m': KLType.KLType_Month
    '3m': KLType.KLType_Quarter
    '1y': KLType.KLType_Year

  @constant: {
    Common
    KLType
    ModifyOrderOp
    OrderStatus
    OrderType
    Qot_Common
    QotMarket
    RehabType
    RetType
    SecurityFirm
    SubType
    TradeDateMarket
    Trd_Common
    TrdEnv
    TrdMarket
    TrdSide
    TrdSecMarket
  }

  trdEnv: if process.env.TRDENV? then parseInt process.env.TRDENV else TrdEnv.TrdEnv_Simulate

  constructor: ({host, port} = {}) ->
    super()
    host ?= 'localhost'
    port ?= 33333
    global.WebSocket = require 'ws'
    return do =>
      await new Promise (resolve, reject) =>
        @ws = new ftWebsocket()
        @ws.start host, port, false, null
        @ws.onlogin = resolve
        @ws.onPush = (cmd, data) =>
          try
            @next
              type: (_.find ftCmdID, cmd: cmd).name
              data: Futu.errHandler data
          catch err
            @error err
      @

  @errHandler: ({errCode, retMsg, retType, s2c}) ->
    if retType != Futu.constant.RetType.RetType_Succeed
      throw new Error "#{errCode}: #{retMsg}"
    else
      s2c

  historyKL: ({market, code, start, end, freq}) ->
    security =
      market: Futu.marketMap[market]
      code: code
    rehabType = RehabType.RehabType_Forward
    klType = Futu.klTypeMap[freq]
    beginTime = (start || moment().subtract freqDuration[freq])
      .format 'YYYY-MM-DD'
    endTime = (end || moment())
      .format 'YYYY-MM-DD HH:mm:ss' 
    {klList} = Futu.errHandler await @ws.RequestHistoryKL c2s: {rehabType, klType, security, beginTime, endTime}
    from klList.map (i) ->
      {timestamp, openPrice, highPrice, lowPrice, closePrice, volume, turnover, changeRate} = i
      market: market
      code: code
      freq: freq
      timestamp: timestamp
      open: openPrice
      high: highPrice
      low: lowPrice
      close: closePrice
      volume: volume.toNumber()
      turnover: turnover
      changeRate: changeRate
    
  streamKL: ({market, code, freq}) ->
    opts = {market, code, freq}
    market ?= 'hk'
    market = Futu.marketMap[market]
    await @ws.Sub
      c2s:
        securityList: [{market, code}]
        subTypeList: [Futu.freqMap[freq]]
        isSubOrUnSub: true
        isRegOrUnRegPush: true
    kl = filter ({type, data}) ->
      {klType, security} = data
      type == 'Qot_UpdateKL' and 
      market == security.market and
      code == security.code and
      Futu.klTypeMap[freq] == klType
    transform = map ({type, data}) ->
      {timestamp, openPrice, highPrice, lowPrice, closePrice, volume, turnover} = data.klList[0]
      market: opts.market
      code: code
      freq: freq
      timestamp: timestamp
      open: openPrice
      high: highPrice
      low: lowPrice
      close: closePrice
      volume: volume.toNumber()
      turnover: turnover
    @pipe kl, transform 

  orderBook: ({market, code}) ->
    opts = {market, code}
    market ?= 'hk'
    market = Futu.marketMap[market]
    await @ws.Sub
      c2s:
        securityList: [{market, code}]
        subTypeList: [Futu.constant.SubType.SubType_OrderBook]
        isSubOrUnSub: true
        isRegOrUnRegPush: true
    orderBook = filter ({type, data}) ->
      {security} = data
      {market, code} = security
      type == 'Qot_UpdateOrderBook' and
      market == security.market and
      code == security.code
    transform = map ({type, data}) ->
      market: opts.market
      code: code
      ask: data.orderBookAskList
      bid: data.orderBookBidList  
    @pipe orderBook, transform

  unsubKL: ({market, code, freq}) ->
    opts = {market, code, freq}
    console.log Futu.subTypeMap[freq]
    console.log opts
    market ?= 'hk'
    market = Futu.marketMap[market]
    await @ws.Sub
      c2s:
        securityList: [{market, code}]
        subTypeList: [Futu.subTypeMap[freq]]
        isSubOrUnSub: false
        isRegOrUnRegPush: true

  unsubOrderBook: ({market, code}) ->
    opts = {market, code}
    market ?= 'hk'
    market = Futu.marketMap[market]
    await @ws.Sub
      c2s:
        securityList: [{market, code}]
        subTypeList: [Futu.constant.SubType.SubType_OrderBook]
        isSubOrUnSub: false
        isRegOrUnRegPush: true
    
  marketState: ({market, code}) ->
    market ?= 'hk'
    market = Futu.marketMap[market]
    (Futu.errHandler await @ws.GetMarketState 
      c2s: securityList: [{market, code}]).marketInfoList

  optionChain: ({market, code, strikeRange, start, end}) ->
    market ?= 'hk'
    start ?= moment()
      .startOf 'month'
    end ?= moment()
      .endOf 'month'
    {optionChain} = Futu.errHandler await @ws.GetOptionChain
      c2s:
        owner:
          market: Futu.marketMap[market]
          code: code
        beginTime: start.format 'YYYY-MM-DD'
        endTime: end.format 'YYYY-MM-DD'
    _.map optionChain, ({option, strikeTime, strikeTimestamp}) ->
      strikeTime: strikeTime
      option: _.filter option, ({call, put}) ->
        {basic, optionExData} = call
        {strikePrice} = optionExData
        [min, max] = strikeRange
        min <= strikePrice and strikePrice <= max

  basicQuote: ({market, code}) ->
    market ?= 'hk'
    market = Futu.marketMap[market]
    await @ws.Sub
      c2s:
        securityList: [{market, code}]
        subTypeList: [Futu.constant.SubType.SubType_Basic]
        isSubOrUnSub: true
        isRegOrUnRegPush: true
    req =
      c2s:
        securityList: [{market, code}]
    [ret, ...] = (Futu.errHandler await @ws.GetBasicQot req).basicQotList
    ret

  plateSecurity: ({market, code} = {}) ->
    market ?= 'hk'
    market = Futu.marketMap[market]
    code ?= 'HSI Constituent'
    (Futu.errHandler await @ws.GetPlateSecurity
      c2s:
        plate: {market, code}).staticInfoList.map ({basic}) ->
          basic.security.code

  accounts: ->
    (Futu.errHandler await @ws.GetAccList c2s: userID: 0)
      .accList
      .filter ({trdEnv, trdMarketAuthList}) ->
        # real account and hk in market list
        trdEnv == 1 and 1 in trdMarketAuthList
      .map (acc) =>
        acc.broker = @
        new Account acc

export default Futu
