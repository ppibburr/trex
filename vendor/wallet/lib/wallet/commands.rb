class Wallet
  def stash args
    target = args[0] || :USDT
              
    get_balances(account,[]).each do |bal|
      next if bal.coin == :BTC
      next if bal.coin == target
      
      market = "BTC-#{bal.coin}"
      `#{order_exe} #{ARGV.find do |a| a =~ /\-\-account\-file\=/ end} --market=#{market} --rate=diff --amount=-1 --sell`
    end

    Trex.idle do
      list = balances.map do |bal| bal.coin end.sort
      if list == [:BTC, target].sort or list == [:BTC]
        `#{order_exe} #{ARGV.find do |a| a =~ /\-\-account\-file\=/ end} --market=USDT-BTC --rate=diff --amount=-1 --sell`
        next false
      else
        next true
      end
    end
  end

  def withdraw *args
    group = wallets[args[0]]
    coin  = args[1].to_s.upcase.to_s.to_sym
    if args[1] and addr = group[coin.to_s]
      if !args[2]
        begin
          message(account.withdraw!(coin, addr)["uuid"])
        rescue => e
          message(e.to_s)
        end
      elsif amt=args[2]
        begin
          amt = Float(amt)
          message(account.withdraw(coin, amt , addr)["uuid"]) 
        rescue => e
          message(e.to_s)
        end
      end
    elsif coin
      begin
        amt = Float(args[2])
        account.withdraw(coin, amt , args[0]) 
      rescue => e
        message(e.to_s)
      end
    end
  end

  def withdrawals *args  
    message(account.withdrawals(args[0] ? args[0].upcase.to_sym : nil).map do |w|
      "#{w.currency} #{w.amount} #{w.txid} #{w.pending}"
    end.join("\n"))
  rescue => e
    message(e.to_s)
  end

  def execute cmd, *args
    case cmd.to_s
    when 'watch'
      if args[0] != "open"
        coin = args[0].to_s.upcase.to_sym
    
        balances << account.balance(coin) unless balances.find do |bal| bal.coin == coin end
        watching << coin                  unless watching.index(coin)
      else
        execute "open"
        oa.each do |o|
          execute "watch", o.market.split("-")[1]
        end
      end
    when "cancel"
      if !args[0] and lo and lo["uuid"]
        `#{order_exe} --cancel='#{lo["uuid"]}' #{ARGV.find do |a| a =~ /\-\-account\-file\=/ end}`
      elsif args[0] == "all"
        `#{order_exe} --cancel=all #{ARGV.find do |a| a =~ /\-\-account\-file\=/ end}`
      elsif args[0] == "market"
        `#{order_exe} --cancel=true --market='#{args[1]}' #{ARGV.find do |a| a =~ /\-\-account\-file\=/ end}`
      elsif args[0] =~ /^([0-9]+)/ and !oa.empty?
        `#{order_exe} --cancel='#{oa[$1.to_i].uuid}' #{ARGV.find do |a| a =~ /\-\-account\-file\=/ end}`
      end
    when 'buy' 
      market = "BTC-#{args[0].upcase}"
      rate   = args[1] || "diff"
      amount = args[2] || -1
      message "BUY Order "+lo=`#{order_exe} #{ARGV.find do |a| a =~ /\-\-account\-file\=/ end} --market=#{market} --rate=#{rate} --amount=#{amount} --buy`
      begin
        self.lo = JSON.parse(lo)
      rescue => e;message e.to_s;
        lo=nil
      end
    when 'sell' 
      market = "BTC-#{args[0].upcase}"
      rate   = args[1] || "diff"
      amount = args[2] || -1
      command = "#{order_exe} #{ARGV.find do |a| a =~ /\-\-account\-file\=/ end} --market=#{market} --rate=#{rate} --amount=#{amount} --sell"
      message "SELL Order "+lo=`#{command}`
      begin
        self.lo = JSON.parse(lo.strip)
      rescue => e ;message e.to_s;
        lo=nil
      end
    when "addr"
      coin = args[0]
      message "#{coin.upcase} Deposit Address: #{account.address(coin)}"
    when "eval"
      message res="#{`ruby -e "p(#{args.join(' ')})"`}"
      screen.puts res if @eval_mode
    when "rate"
      if args[0] == "gdax"
        update_gdax unless @enable_gdax
        message "Rate: Using GDAX for USD conversion" 
      end
      message "Rate: using bittrex market data" if !args[0]
      @btc_rate_override = args[0]
    when "api-rate"
      message Trex::JSONApi.rate.to_s
    when "uuid"
      if !args[0] and lo and uuid=lo["uuid"]
        message "Laster Order UUID: #{uuid}"
      elsif !oa.empty? and idx=args[0]
        o = oa[idx.to_i]
        message("UUID: #{o.uuid}")
      else
        message "UUID: No Orders this Session"
      end
    when "open"
      if args[0].to_s =~ /^([0-9]+)/
        o = oa[idx=$1.to_i]
        
        if !o
          message("No order")
          return
        end
        
        message([
          "Index: #{idx}", "Market: #{o.market}", "Rate: #{o.limit}",
          "Amount: #{o.quantity}",
          "Type: #{o.type}"
        ].join(", "))
        return
      end
    
      self.oa = account.orders.find_all do |o|
        args[0] ? o.market == args[0] : true
      end
      
      idx=-1
      a=oa.map do |o|
        [
          "Index: #{idx+=1}",
          "Market: #{o.market}",
          "Rate: #{o.limit}",
          "Amount: #{o.quantity}",
          "Type: #{o.type}"
        ].join(", ")
      end
      message(a.empty? ? "No Orders" : a.join("\n"))
    when "repeat"
      repeat *args
    when "nonzero"
      balances.find_all do |bal| watching.index bal.coin end.each do |bal| balances.delete bal end
      self.watching = []
    when "withdrawals"
      withdrawals *args
    when "withdraw"
      withdraw *args
    when "stash"
      stash()
    when "clear"
      screen.clear
    when "toggle"
      @update = !@update
      screen.clear
    when "view"
      if !(what=args[0])
        @update = true
        screen.clear
      elsif what == "open"
        @update=false
        screen.clear
        execute what, *args[1..-1]

        @msg_buff.split("\n").each do |l| screen.puts l end
      elsif what == "withdrawals"
        @update=false
        
        screen.clear
        
        execute what, *args[1..-1]
        
        @msg_buff.split("\n").each do |l| screen.puts l end
      elsif what == "eval"
        @eval_mode = true
      elsif what == "addr"
        @update = false
        screen.clear
        execute what, *args[1..-1]
      elsif what == "halt"
        @update = false
      end
    end
  rescue => e
    message e.to_s
  end
  
  def repeat coin, buyin, target, amt=nil
    coin = coin.to_s.upcase.to_sym
    
    execute "watch", coin.to_s
    execute "watch", "BTC"
    
    buyin  = buyin.to_f
    target = target.to_f
    amt    = amt.to_f    if amt
    
    amt = nil if amt == -1
    
    uuid = order = nil
    
    if order=@open.find do |o| o.market == "BTC-#{coin}" end
      uuid = order.uuid
    else
      cb = balances.find do |q| q.coin.to_sym == coin end
      b  = balances.find do |q| q.coin.to_sym == :BTC end
      
      if cb and b
        if cb.btc > b.avail
          a = amt
          a = (cb.avail * cb.rate) / amt  if a
          execute "sell", "#{coin}", target.trex_s, (a ? a.trex_s : "-1")      
        else
          execute "buy", coin, buyin.trex_s, (amt ? amt.trex_s : "-1")
        end
      elsif b and b.avail > 0.0005
        execute "buy", coin, buyin.trex_s, (amt ? amt.trex_s : "-1")
      end
      
      if lo
        uuid = lo['uuid']
      end
    end
    
    if uuid
      on_order_closed do |o|
        message o.type
        if o.uuid == uuid
          if o.type == "LIMIT_SELL"
            execute "repeat", coin, buyin.trex_s, target.trex_s, ((a=(amt || -1)) == -1 ? "-1" : a.trex_s)
            next if lo
          elsif o.type == "LIMIT_BUY"
            execute "sell", coin.to_s, target.trex_s, ((o.price / o.price_per_unit)*0.9975).to_s
            if lo
              execute "repeat", coin.to_s, buyin.trex_s, target.trex_s, ((a=(amt || -1)) == -1 ? "-1" : a.trex_s)
              next
            end
          end
        end
        
        message "Repeat: #{coin} - END"
      end
    else
      message "Repeat: #{coin} - END"
    end
  rescue => e
    raise e
  end
end