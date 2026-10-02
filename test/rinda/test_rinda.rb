# frozen_string_literal: false
require 'test/unit'
require 'envutil'

require 'drb/drb'
require 'drb/eq'
require 'rinda/ring'
require 'rinda/tuplespace'
require 'timeout'
require 'singleton'

module Rinda

class MockClock
  include Singleton

  class MyTS < Rinda::TupleSpace
    def keeper_thread
      nil
    end

    def stop_keeper
      if @keeper
        @keeper.kill
        @keeper.join
        @keeper = nil
      end
    end
  end

  def initialize
    @now = 2
    @reso = 1
    @ts = nil
    @inf = 2**31 - 1
  end

  def start_keeper
    @now = 2
    @reso = 1
    @ts&.stop_keeper
    @ts = MyTS.new
    @ts.write([2, :now])
    @inf = 2**31 - 1
  end

  def stop_keeper
    @ts.stop_keeper
  end

  def now
    @now.to_f
  end

  def at(n)
    n
  end

  def _forward(n=nil)
    now ,= @ts.take([nil, :now])
    @now = now + n
    @ts.write([@now, :now])
  end

  def forward(n)
    while n > 0
      _forward(@reso)
      n -= @reso
      Thread.pass
    end
  end

  def rewind
    @ts.take([nil, :now])
    @ts.write([@inf, :now])
    @ts.take([nil, :now])
    @now = 2
    @ts.write([2, :now])
  end

  def sleep(n=nil)
    now ,= @ts.read([nil, :now])
    @ts.read([(now + n)..@inf, :now])
    0
  end
end

module Time
  def sleep(n)
    @m.sleep(n)
  end
  module_function :sleep

  def at(n)
    n
  end
  module_function :at

  def now
    defined?(@m) && @m ? @m.now : 2
  end
  module_function :now

  def rewind
    @m.rewind
  end
  module_function :rewind

  def forward(n)
    @m.forward(n)
  end
  module_function :forward

  @m = MockClock.instance
end

class TupleSpace
  def sleep(n)
    Kernel.sleep(n * 0.01)
  end
end

module TupleSpaceTestModule
  def setup
    MockClock.instance.start_keeper
  end

  def teardown
    MockClock.instance.stop_keeper
  end

  def sleep(n)
    if Thread.current == Thread.main
      Time.forward(n)
    else
      Time.sleep(n)
    end
  end

  def thread_join(th)
    while th.alive?
      Kernel.sleep(0.1)
      sleep(1)
    end
    th.value
  end

  def test_00_tuple
    tuple = Rinda::TupleEntry.new([1,2,3])
    assert(!tuple.canceled?)
    assert(!tuple.expired?)
    assert(tuple.alive?)
  end

  def test_00_template
    tmpl = Rinda::Template.new([1,2,3])
    assert_equal(3, tmpl.size)
    assert_equal(3, tmpl[2])
    assert(tmpl.match([1,2,3]))
    assert(!tmpl.match([1,nil,3]))

    tmpl = Rinda::Template.new([/^rinda/i, nil, :hello])
    assert_equal(3, tmpl.size)
    assert(tmpl.match(['Rinda', 2, :hello]))
    assert(!tmpl.match(['Rinda', 2, Symbol]))
    assert(!tmpl.match([1, 2, :hello]))
    assert(tmpl.match([/^rinda/i, 2, :hello]))

    tmpl = Rinda::Template.new([Symbol])
    assert_equal(1, tmpl.size)
    assert(tmpl.match([:hello]))
    assert(tmpl.match([Symbol]))
    assert(!tmpl.match(['Symbol']))

    tmpl = Rinda::Template.new({"message"=>String, "name"=>String})
    assert_equal(2, tmpl.size)
    assert(tmpl.match({"message"=>"Hello", "name"=>"Foo"}))
    assert(!tmpl.match({"message"=>"Hello", "name"=>"Foo", "1"=>2}))
    assert(!tmpl.match({"message"=>"Hi", "name"=>"Foo", "age"=>1}))
    assert(!tmpl.match({"message"=>"Hello", "no_name"=>"Foo"}))

    assert_raise(Rinda::InvalidHashTupleKey) do
      Rinda::Template.new({:message=>String, "name"=>String})
    end
    tmpl = Rinda::Template.new({"name"=>String})
    assert_equal(1, tmpl.size)
    assert(tmpl.match({"name"=>"Foo"}))
    assert(!tmpl.match({"message"=>"Hello", "name"=>"Foo"}))
    assert(!tmpl.match({"message"=>:symbol, "name"=>"Foo", "1"=>2}))
    assert(!tmpl.match({"message"=>"Hi", "name"=>"Foo", "age"=>1}))
    assert(!tmpl.match({"message"=>"Hello", "no_name"=>"Foo"}))

    tmpl = Rinda::Template.new({"message"=>String, "name"=>String})
    assert_equal(2, tmpl.size)
    assert(tmpl.match({"message"=>"Hello", "name"=>"Foo"}))
    assert(!tmpl.match({"message"=>"Hello", "name"=>"Foo", "1"=>2}))
    assert(!tmpl.match({"message"=>"Hi", "name"=>"Foo", "age"=>1}))
    assert(!tmpl.match({"message"=>"Hello", "no_name"=>"Foo"}))

    tmpl = Rinda::Template.new({"message"=>String})
    assert_equal(1, tmpl.size)
    assert(tmpl.match({"message"=>"Hello"}))
    assert(!tmpl.match({"message"=>"Hello", "name"=>"Foo"}))
    assert(!tmpl.match({"message"=>"Hello", "name"=>"Foo", "1"=>2}))
    assert(!tmpl.match({"message"=>"Hi", "name"=>"Foo", "age"=>1}))
    assert(!tmpl.match({"message"=>"Hello", "no_name"=>"Foo"}))

    tmpl = Rinda::Template.new({"message"=>String, "name"=>nil})
    assert_equal(2, tmpl.size)
    assert(tmpl.match({"message"=>"Hello", "name"=>"Foo"}))
    assert(!tmpl.match({"message"=>"Hello", "name"=>"Foo", "1"=>2}))
    assert(!tmpl.match({"message"=>"Hi", "name"=>"Foo", "age"=>1}))
    assert(!tmpl.match({"message"=>"Hello", "no_name"=>"Foo"}))

    assert_raise(Rinda::InvalidHashTupleKey) do
      @ts.write({:message=>String, "name"=>String})
    end

    @ts.write([1, 2, 3])
    assert_equal([1, 2, 3], @ts.take([1, 2, 3]))

    @ts.write({'1'=>1, '2'=>2, '3'=>3})
    assert_equal({'1'=>1, '2'=>2, '3'=>3}, @ts.take({'1'=>1, '2'=>2, '3'=>3}))

    entry = @ts.write(['1'=>1, '2'=>2, '3'=>3])
    assert_raise(Rinda::RequestExpiredError) do
      assert_equal({'1'=>1, '2'=>2, '3'=>3}, @ts.read({'1'=>1}, 0))
    end
    entry.cancel
  end

  def test_00_DRbObject
    ro = DRbObject.new(nil, "druby://host:1234")
    tmpl = Rinda::DRbObjectTemplate.new
    assert(tmpl === ro)

    tmpl = Rinda::DRbObjectTemplate.new("druby://host:1234")
    assert(tmpl === ro)

    tmpl = Rinda::DRbObjectTemplate.new("druby://host:12345")
    assert(!(tmpl === ro))

    tmpl = Rinda::DRbObjectTemplate.new(/^druby:\/\/host:/)
    assert(tmpl === ro)

    ro = DRbObject.new_with(12345, 1234)
    assert(!(tmpl === ro))

    ro = DRbObject.new_with("druby://foo:12345", 1234)
    assert(!(tmpl === ro))

    tmpl = Rinda::DRbObjectTemplate.new(/^druby:\/\/(foo|bar):/)
    assert(tmpl === ro)

    ro = DRbObject.new_with("druby://bar:12345", 1234)
    assert(tmpl === ro)

    ro = DRbObject.new_with("druby://baz:12345", 1234)
    assert(!(tmpl === ro))
  end

  def test_inp_rdp
    assert_raise(Rinda::RequestExpiredError) do
      @ts.take([:empty], 0)
    end

    assert_raise(Rinda::RequestExpiredError) do
      @ts.read([:empty], 0)
    end
  end

  def test_ruby_talk_264062
    th = Thread.new {
      assert_raise(Rinda::RequestExpiredError) do
        @ts.take([:empty], 1)
      end
    }
    sleep(10)
    thread_join(th)

    th = Thread.new {
      assert_raise(Rinda::RequestExpiredError) do
        @ts.read([:empty], 1)
      end
    }
    sleep(10)
    thread_join(th)
  end

  def test_symbol_tuple
    @ts.write([:symbol, :symbol])
    @ts.write(['string', :string])
    assert_equal([[:symbol, :symbol]], @ts.read_all([:symbol, nil]))
    assert_equal([[:symbol, :symbol]], @ts.read_all([Symbol, nil]))
    assert_equal([], @ts.read_all([:nil, nil]))
  end

  def test_core_01
    5.times do
      @ts.write([:req, 2])
    end

    assert_equal([[:req, 2], [:req, 2], [:req, 2], [:req, 2], [:req, 2]],
		 @ts.read_all([nil, nil]))

    taker = Thread.new(5) do |count|
      s = 0
      count.times do
        tuple = @ts.take([:req, Integer])
        assert_equal(2, tuple[1])
        s += tuple[1]
      end
      @ts.write([:ans, s])
      s
    end

    assert_equal(10, thread_join(taker))
    assert_equal([:ans, 10], @ts.take([:ans, 10]))
    assert_equal([], @ts.read_all([nil, nil]))
  end

  def test_core_02
    taker = Thread.new(5) do |count|
      s = 0
      count.times do
        tuple = @ts.take([:req, Integer])
        assert_equal(2, tuple[1])
        s += tuple[1]
      end
      @ts.write([:ans, s])
      s
    end

    5.times do
      @ts.write([:req, 2])
    end

    assert_equal(10, thread_join(taker))
    assert_equal([:ans, 10], @ts.take([:ans, 10]))
    assert_equal([], @ts.read_all([nil, nil]))
  end

  def test_core_03_notify
    notify1 = @ts.notify(nil, [:req, Integer])
    notify2 = @ts.notify(nil, {"message"=>String, "name"=>String})

    5.times do
      @ts.write([:req, 2])
    end

    5.times do
      tuple = @ts.take([:req, Integer])
      assert_equal(2, tuple[1])
    end

    5.times do
      assert_equal(['write', [:req, 2]], notify1.pop)
    end
    5.times do
      assert_equal(['take', [:req, 2]], notify1.pop)
    end

    @ts.write({"message"=>"first", "name"=>"3"})
    @ts.write({"message"=>"second", "name"=>"1"})
    @ts.write({"message"=>"third", "name"=>"0"})
    @ts.take({"message"=>"third", "name"=>"0"})
    @ts.take({"message"=>"first", "name"=>"3"})

    assert_equal(["write", {"message"=>"first", "name"=>"3"}], notify2.pop)
    assert_equal(["write", {"message"=>"second", "name"=>"1"}], notify2.pop)
    assert_equal(["write", {"message"=>"third", "name"=>"0"}], notify2.pop)
    assert_equal(["take", {"message"=>"third", "name"=>"0"}], notify2.pop)
    assert_equal(["take", {"message"=>"first", "name"=>"3"}], notify2.pop)
  end

  def test_cancel_01
    entry = @ts.write([:removeme, 1])
    assert_equal([[:removeme, 1]], @ts.read_all([nil, nil]))
    entry.cancel
    assert_equal([], @ts.read_all([nil, nil]))

    template = nil
    taker = Thread.new do
      assert_raise(Rinda::RequestCanceledError) do
        @ts.take([:take, nil], 10) do |t|
          template = t
          Thread.new do
            template.cancel
          end
        end
      end
    end

    sleep(2)
    thread_join(taker)

    assert(template.canceled?)

    @ts.write([:take, 1])

    assert_equal([[:take, 1]], @ts.read_all([nil, nil]))
  end

  def test_cancel_02
    omit 'this test is unstable with --jit-wait' if defined?(RubyVM::RJIT) && RubyVM::RJIT.enabled?
    entry = @ts.write([:removeme, 1])
    assert_equal([[:removeme, 1]], @ts.read_all([nil, nil]))
    entry.cancel
    assert_equal([], @ts.read_all([nil, nil]))

    template = nil
    reader = Thread.new do
      assert_raise(Rinda::RequestCanceledError) do
        @ts.read([:take, nil], 10) do |t|
          template = t
          Thread.new do
            template.cancel
          end
        end
      end
    end

    sleep(2)
    thread_join(reader)

    assert(template.canceled?)

    @ts.write([:take, 1])

    assert_equal([[:take, 1]], @ts.read_all([nil, nil]))
  end

  def test_take_all_basic
    @ts.write([:task, 1])
    @ts.write([:res, 'a'])
    @ts.write([:res, 'b'])

    assert_equal([[:task, 1], [:res, 'a'], [:res, 'b']],
                 @ts.take_all([[:task, Integer], [:res, String], [:res, String]], 0))
    assert_equal([], @ts.read_all([nil, nil]))
  end

  def test_take_all_immediate_and_wait_return_same_order
    @ts.write([:a, 1])
    @ts.write([:b, 2])
    immediate = @ts.take_all([[:b, nil], [:a, nil]], 0)
    assert_equal([[:b, 2], [:a, 1]], immediate)

    @ts.write([:a, 1])
    @ts.write([:b, 2])
    assert_equal(immediate, @ts.take_all([[:b, nil], [:a, nil]]))
    assert_equal([], @ts.read_all([nil, nil]))
  end

  def test_take_all_overlapping_templates
    # written in this order, a greedy assignment in template order would
    # take [:b] for [nil] and then find nothing for [:b]
    @ts.write([:b])
    @ts.write([:a])

    assert_equal([[:a], [:b]], @ts.take_all([[nil], [:b]], 0))
    assert_equal([], @ts.read_all([nil]))
  end

  def test_take_all_duplicate_tuples_are_distinct
    @ts.write([:x, 1])
    assert_raise(Rinda::RequestExpiredError) do
      @ts.take_all([[:x, 1], [:x, 1]], 0)
    end
    assert_equal([[:x, 1]], @ts.read_all([:x, nil]))

    @ts.write([:x, 1])
    assert_equal([[:x, 1], [:x, 1]], @ts.take_all([[:x, 1], [:x, 1]], 0))
    assert_equal([], @ts.read_all([nil, nil]))
  end

  def test_take_all_failure_removes_nothing
    @ts.write([:task, 1])
    assert_raise(Rinda::RequestExpiredError) do
      @ts.take_all([[:task, nil], [:res, nil]], 0)
    end
    assert_equal([[:task, 1]], @ts.read_all([nil, nil]))
  end

  def test_take_all_waits_for_whole_group
    started = Queue.new
    result = Queue.new
    consumer = Thread.new do
      result.push(@ts.take_all([[:task, nil], [:res, nil]]) do |w|
        started.push(true)
      end)
    end
    started.pop

    @ts.write([:task, 1])
    # the group is incomplete, so the tuple must not be removed
    assert_equal([[:task, 1]], @ts.read_all([nil, nil]))

    @ts.write([:res, 'r'])
    assert_equal([[:task, 1], [:res, 'r']], result.pop)
    consumer.join
    assert_equal([], @ts.read_all([nil, nil]))
  end

  def test_take_all_timeout_removes_nothing
    @ts.write([:task, 1])
    consumer = Thread.new do
      assert_raise(Rinda::RequestExpiredError) do
        @ts.take_all([[:task, nil], [:res, nil]], 1)
      end
    end
    sleep(10)
    thread_join(consumer)
    assert_equal([[:task, 1]], @ts.read_all([nil, nil]))
  end

  def test_take_all_cancel_removes_nothing
    @ts.write([:task, 1])
    template = nil
    consumer = Thread.new do
      assert_raise(Rinda::RequestCanceledError) do
        @ts.take_all([[:task, nil], [:res, nil]], 10) do |t|
          template = t
          Thread.new do
            t.cancel
          end
        end
      end
    end
    sleep(2)
    thread_join(consumer)

    assert(template.canceled?)
    assert_equal([[:task, 1]], @ts.read_all([nil, nil]))
  end

  def test_take_all_reevaluates_after_tuple_expires
    @ts.write([:task, 1], 1)
    started = Queue.new
    result = Queue.new
    consumer = Thread.new do
      result.push(@ts.take_all([[:task, nil], [:res, nil]], 30) do |w|
        started.push(true)
      end)
    end
    started.pop

    sleep(2) # let [:task, 1] expire
    wait_until { @ts.read_all([nil, nil]).empty? }

    @ts.write([:res, 'r'])
    @ts.write([:task, 2])
    assert_equal([[:task, 2], [:res, 'r']], result.pop)
    consumer.join
    assert_equal([], @ts.read_all([nil, nil]))
  end

  def test_take_all_reevaluates_when_tuples_taken
    started = Queue.new
    result = Queue.new
    consumer = Thread.new do
      result.push(@ts.take_all([[:task, nil], [:res, nil]]) do |w|
        started.push(true)
      end)
    end
    started.pop

    @ts.write([:task, 1])
    # another consumer grabs the only :task tuple first
    assert_equal([:task, 1], @ts.take([:task, nil], 0))

    @ts.write([:res, 'r'])
    @ts.write([:task, 2])
    assert_equal([[:task, 2], [:res, 'r']], result.pop)
    consumer.join
    assert_equal([], @ts.read_all([nil, nil]))
  end

  def test_take_all_exhaustive_small_spaces
    tuple_pool = [[:a], [:b]]
    template_pool = [[nil], [:a], [:b]]

    spaces = (0..3).flat_map do |n|
      tuple_pool.repeated_permutation(n).to_a
    end
    template_sets = (1..3).flat_map do |n|
      template_pool.repeated_permutation(n).to_a
    end

    solvable = 0
    spaces.each do |tuples|
      template_sets.each do |templates|
        expected = templates.size <= tuples.size &&
          (0...tuples.size).to_a.permutation.any? do |perm|
            perm.first(templates.size).each_with_index.all? do |ti, i|
              Rinda::Template.new(templates[i]).match(tuples[ti])
            end
          end

        tuples.each do |tuple|
          @ts.write(tuple)
        end
        begin
          if expected
            solvable += 1
            result = @ts.take_all(templates, 0)
            assert_equal(templates.size, result.size,
                         "space=#{tuples.inspect} templates=#{templates.inspect}")
            used = Array.new(tuples.size, false)
            result.each_with_index do |tuple, i|
              assert(Rinda::Template.new(templates[i]).match(tuple),
                     "template #{templates[i].inspect} does not match #{tuple.inspect}")
              idx = tuples.each_index.find do |j|
                !used[j] && tuples[j] == tuple
              end
              assert(idx, "returned #{tuple.inspect} is not in #{tuples.inspect}")
              used[idx] = true
            end
            remaining = tuples.each_with_index.reject do |_, j|
              used[j]
            end.map(&:first)
            assert_equal(remaining.sort, @ts.read_all([nil]).sort,
                         "space=#{tuples.inspect} templates=#{templates.inspect}")
          else
            assert_raise(Rinda::RequestExpiredError,
                         "space=#{tuples.inspect} templates=#{templates.inspect}") do
              @ts.take_all(templates, 0)
            end
            assert_equal(tuples.sort, @ts.read_all([nil]).sort,
                         "space=#{tuples.inspect} templates=#{templates.inspect}")
          end
        ensure
          @ts.read_all([nil]).each do |tuple|
            @ts.take(tuple, 0)
          end
        end
      end
    end
    assert(solvable > 0, 'expected some solvable cases')
    assert(solvable < spaces.size * template_sets.size,
           'expected some unsolvable cases')
  end

  def wait_until
    Timeout.timeout(10) do
      Thread.pass until yield
    end
  end

  class SimpleRenewer
    def initialize(sec, n = 1)
      @sec = sec
      @n = n
    end

    def renew
      return -1 if @n <= 0
      @n -= 1
      return @sec
    end
  end

  def test_00_renewer
    tuple = Rinda::TupleEntry.new([1,2,3], true)
    assert(!tuple.canceled?)
    assert(tuple.expired?)
    assert(!tuple.alive?)

    tuple = Rinda::TupleEntry.new([1,2,3], 1)
    assert(!tuple.canceled?)
    assert(!tuple.expired?)
    assert(tuple.alive?)
    sleep(2)
    assert(tuple.expired?)
    assert(!tuple.alive?)

    @renewer = SimpleRenewer.new(1,2)
    tuple = Rinda::TupleEntry.new([1,2,3], @renewer)
    assert(!tuple.canceled?)
    assert(!tuple.expired?)
    assert(tuple.alive?)
    sleep(1)
    assert(!tuple.canceled?)
    assert(!tuple.expired?)
    assert(tuple.alive?)
    sleep(2)
    assert(tuple.expired?)
    assert(!tuple.alive?)
  end
end

class TupleSpaceTest < Test::Unit::TestCase
  include TupleSpaceTestModule

  def setup
    super
    ThreadGroup.new.add(Thread.current)
    @ts = Rinda::TupleSpace.new(1)
  end
  def teardown
    # implementation-dependent
    @ts.instance_eval{
      if th = @keeper
        th.kill
        th.join
      end
    }
    super
  end
end

class TupleSpaceProxyTest < Test::Unit::TestCase
  include TupleSpaceTestModule

  def setup
    if RUBY_PLATFORM.match?(/mingw/)
      @omitted = true
      omit 'This test seems to randomly hang on GitHub Actions MinGW'
    end
    super
    ThreadGroup.new.add(Thread.current)
    @ts_base = Rinda::TupleSpace.new(1)
    @ts = Rinda::TupleSpaceProxy.new(@ts_base)
    @server = DRb.start_service("druby://localhost:0")
  end
  def teardown
    return if @omitted
    @omitted = false

    # implementation-dependent
    @ts_base.instance_eval{
      if th = @keeper
        th.kill
        th.join
      end
    }
    @server.stop_service
    DRb::DRbConn.stop_pool
    super
  end

  def test_remote_array_and_hash
    # Don't remove ary/hsh local variables.
    # These are necessary to protect objects from GC.
    ary = [1, 2, 3]
    @ts.write(DRbObject.new(ary))
    assert_equal([1, 2, 3], @ts.take([1, 2, 3], 0))
    hsh = {'head' => 1, 'tail' => 2}
    @ts.write(DRbObject.new(hsh))
    assert_equal({'head' => 1, 'tail' => 2},
                 @ts.take({'head' => 1, 'tail' => 2}, 0))
  end

  def test_take_bug_8215
    omit "this test randomly fails on mswin" if /mswin/ =~ RUBY_PLATFORM
    service = DRb.start_service("druby://localhost:0", @ts_base)

    uri = service.uri

    args = [EnvUtil.rubybin, *%W[-rdrb/drb -rdrb/eq -rrinda/ring -rrinda/tuplespace -e]]

    take = spawn(*args, <<-'end;', uri)
      uri = ARGV[0]
      DRb.start_service("druby://localhost:0")
      ro = DRbObject.new_with_uri(uri)
      ts = Rinda::TupleSpaceProxy.new(ro)
      th = Thread.new do
        ts.take([:test_take, nil])
      rescue Interrupt
        # Expected
      end
      Kernel.sleep(0.1)
      th.raise(Interrupt) # causes loss of the taken tuple
      ts.write([:barrier, :continue])
      Kernel.sleep
    end;

    @ts_base.take([:barrier, :continue])

    write = spawn(*args, <<-'end;', uri)
      uri = ARGV[0]
      DRb.start_service("druby://localhost:0")
      ro = DRbObject.new_with_uri(uri)
      ts = Rinda::TupleSpaceProxy.new(ro)
      ts.write([:test_take, 42])
    end;

    status = Process.wait(write)

    assert_equal([[:test_take, 42]], @ts_base.read_all([:test_take, nil]),
                 '[bug:8215] tuple lost')
  ensure
    service.stop_service if service
    DRb::DRbConn.stop_pool
    signal = /mswin|mingw/ =~ RUBY_PLATFORM ? "KILL" : "TERM"
    Process.kill(signal, write) if write && status.nil?
    Process.kill(signal, take)  if take
    Process.wait(write) if write && status.nil?
    Process.wait(take)  if take
  end
end

module RingIPv4
  def ipv4_mc(rf)
    begin
      v4mc = rf.make_socket('239.0.0.1')
    rescue Errno::ENETUNREACH, Errno::ENOBUFS, Errno::ENODEV
      omit 'IPv4 multicast not available'
    end

    begin
      yield v4mc
    ensure
      v4mc.close
    end
  end
end

module RingIPv6
  def prepare_ipv6(r)
    begin
      Socket.getifaddrs.each do |ifaddr|
        next unless ifaddr.addr
        next unless ifaddr.addr.ipv6_linklocal?
        next if ifaddr.name[0, 2] == "lo"
        r.multicast_interface = ifaddr.ifindex
        return ifaddr
      end
    rescue NotImplementedError
      # ifindex() function may not be implemented on Windows.
      return if
        Socket.ip_address_list.any? { |addrinfo| addrinfo.ipv6? && !addrinfo.ipv6_loopback? }
    end
    omit 'IPv6 not available'
  end

  def ipv6_mc(rf, hops = nil)
    ifaddr = prepare_ipv6(rf)
    rf.multicast_hops = hops if hops
    begin
      v6mc = rf.make_socket("ff02::1")
    rescue Errno::EINVAL
      # somehow Debian 6.0.7 needs ifname
      v6mc = rf.make_socket("ff02::1%#{ifaddr.name}")
    rescue Errno::EADDRNOTAVAIL
      return # IPv6 address for multicast not available
    rescue Errno::ENETDOWN
      return # Network is down
    rescue Errno::EHOSTUNREACH
      return # Unreachable for some reason
    end
    begin
      yield v6mc
    ensure
      v6mc.close
    end
  end
end

class TestRingServer < Test::Unit::TestCase
  include RingIPv4

  def setup
    @port = Rinda::Ring_PORT

    @ts = Rinda::TupleSpace.new
    @rs = Rinda::RingServer.new(@ts, [], @port)
    @server = DRb.start_service("druby://localhost:0")
  end
  def teardown
    @rs.shutdown
    # implementation-dependent
    @ts.instance_eval{
      if th = @keeper
        th.kill
        th.join
      end
    }
    @server.stop_service
    DRb::DRbConn.stop_pool
  end

  def test_do_reply
    with_timeout(30) {_test_do_reply}
  end

  def _test_do_reply
    called = nil

    callback_orig = proc { |ts|
      called = ts
    }

    callback = DRb::DRbObject.new callback_orig

    @ts.write [:lookup_ring, callback]

    @rs.do_reply

    wait_for(30) {called}

    assert_same @ts, called
  end

  def test_do_reply_local
    omit 'timeout-based test becomes unstable with --jit-wait' if defined?(RubyVM::RJIT) && RubyVM::RJIT.enabled?
    with_timeout(30) {_test_do_reply_local}
  end

  def _test_do_reply_local
    called = nil

    callback = proc { |ts|
      called = ts
    }

    @ts.write [:lookup_ring, callback]

    @rs.do_reply

    wait_for(30) {called}

    assert_same @ts, called
  end

  def test_make_socket_unicast
    v4 = @rs.make_socket('127.0.0.1')

    assert_equal('127.0.0.1', v4.local_address.ip_address)
    assert_equal(@port,       v4.local_address.ip_port)
  end

  def test_make_socket_ipv4_multicast
    ipv4_mc(@rs) do |v4mc|
      begin
        if Socket.const_defined?(:SO_REUSEPORT) then
          assert(v4mc.getsockopt(:SOCKET, :SO_REUSEPORT).bool)
        else
          assert(v4mc.getsockopt(:SOCKET, :SO_REUSEADDR).bool)
        end
      rescue TypeError
        if /aix/ =~ RUBY_PLATFORM
          omit "Known bug in getsockopt(2) on AIX"
        end
        raise $!
      end

      assert_equal('0.0.0.0', v4mc.local_address.ip_address)
      assert_equal(@port,     v4mc.local_address.ip_port)
    end
  end

  def test_make_socket_ipv6_multicast
    omit 'IPv6 not available' unless
      Socket.ip_address_list.any? { |addrinfo| addrinfo.ipv6? && !addrinfo.ipv6_loopback? }

    begin
      v6mc = @rs.make_socket('ff02::1')
    rescue Errno::EADDRNOTAVAIL
      return # IPv6 address for multicast not available
    rescue Errno::ENOBUFS => e
      omit "Missing multicast support in OS: #{e.message}"
    end

    if Socket.const_defined?(:SO_REUSEPORT) then
      assert v6mc.getsockopt(:SOCKET, :SO_REUSEPORT).bool
    else
      assert v6mc.getsockopt(:SOCKET, :SO_REUSEADDR).bool
    end

    assert_equal('::1', v6mc.local_address.ip_address)
    assert_equal(@port, v6mc.local_address.ip_port)
  end

  def test_ring_server_ipv4_multicast
    @rs.shutdown
    begin
      @rs = Rinda::RingServer.new(@ts, [['239.0.0.1', '0.0.0.0']], @port)
    rescue Errno::ENOBUFS, Errno::ENODEV => e
      omit "Missing multicast support in OS: #{e.message}"
    end

    v4mc = @rs.instance_variable_get('@sockets').first

    begin
      if Socket.const_defined?(:SO_REUSEPORT) then
        assert(v4mc.getsockopt(:SOCKET, :SO_REUSEPORT).bool)
      else
        assert(v4mc.getsockopt(:SOCKET, :SO_REUSEADDR).bool)
      end
    rescue TypeError
      if /aix/ =~ RUBY_PLATFORM
        omit "Known bug in getsockopt(2) on AIX"
      end
      raise $!
    end

    assert_equal('0.0.0.0', v4mc.local_address.ip_address)
    assert_equal(@port,     v4mc.local_address.ip_port)
  end

  def test_ring_server_ipv6_multicast
    omit 'IPv6 not available' unless
      Socket.ip_address_list.any? { |addrinfo| addrinfo.ipv6? && !addrinfo.ipv6_loopback? }

    @rs.shutdown
    begin
      @rs = Rinda::RingServer.new(@ts, [['ff02::1', '::1', 0]], @port)
    rescue Errno::EADDRNOTAVAIL
      return # IPv6 address for multicast not available
    end

    v6mc = @rs.instance_variable_get('@sockets').first

    if Socket.const_defined?(:SO_REUSEPORT) then
      assert v6mc.getsockopt(:SOCKET, :SO_REUSEPORT).bool
    else
      assert v6mc.getsockopt(:SOCKET, :SO_REUSEADDR).bool
    end

    assert_equal('::1', v6mc.local_address.ip_address)
    assert_equal(@port, v6mc.local_address.ip_port)
  end

  def test_shutdown
    @rs.shutdown

    assert_nil(@rs.do_reply, 'otherwise should hang forever')
  end

  private

  def with_timeout(n)
    aoe = Thread.abort_on_exception
    Thread.abort_on_exception = true
    tl0 = Thread.list
    tl = nil
    th = Thread.new(Thread.current) do |mth|
      sleep n
      (tl = Thread.list - tl0).each {|t|t.raise(Timeout::Error)}
      mth.raise(Timeout::Error)
    end
    tl0 << th
    yield
  rescue Timeout::Error => e
    $stderr.puts "TestRingServer#with_timeout: timeout in #{n}s:"
    $stderr.puts caller
    if tl
      bt = e.backtrace
      tl.each do |t|
        begin
          t.value
        rescue Timeout::Error => e
          bt.unshift("")
          bt[0, 0] = e.backtrace
        end
      end
    end
    raise Timeout::Error, "timeout", bt
  ensure
    if th
      th.kill
      th.join
    end
    Thread.abort_on_exception = aoe
  end

  def wait_for(n)
    t = n + Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
    until yield
      if t < Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
        flunk "timeout during waiting call"
      end
      sleep 0.1
    end
  end
end

class TestRingFinger < Test::Unit::TestCase
  include RingIPv6
  include RingIPv4

  def setup
    @rf = Rinda::RingFinger.new
  end

  def test_make_socket_unicast
    v4 = @rf.make_socket('127.0.0.1')

    assert(v4.getsockopt(:SOL_SOCKET, :SO_BROADCAST).bool)
  rescue TypeError
    if /aix/ =~ RUBY_PLATFORM
      omit "Known bug in getsockopt(2) on AIX"
    end
    raise $!
  ensure
    v4.close if v4
  end

  def test_make_socket_ipv4_multicast
    ipv4_mc(@rf) do |v4mc|
      assert_equal(1, v4mc.getsockopt(:IPPROTO_IP, :IP_MULTICAST_LOOP).ipv4_multicast_loop)
      assert_equal(1, v4mc.getsockopt(:IPPROTO_IP, :IP_MULTICAST_TTL).ipv4_multicast_ttl)
    end
  end

  def test_make_socket_ipv6_multicast
    ipv6_mc(@rf) do |v6mc|
      assert_equal(1, v6mc.getsockopt(:IPPROTO_IPV6, :IPV6_MULTICAST_LOOP).int)
      assert_equal(1, v6mc.getsockopt(:IPPROTO_IPV6, :IPV6_MULTICAST_HOPS).int)
    end
  end

  def test_make_socket_ipv4_multicast_hops
    @rf.multicast_hops = 2
    ipv4_mc(@rf) do |v4mc|
      assert_equal(2, v4mc.getsockopt(:IPPROTO_IP, :IP_MULTICAST_TTL).ipv4_multicast_ttl)
    end
  end

  def test_make_socket_ipv6_multicast_hops
    ipv6_mc(@rf, 2) do |v6mc|
      assert_equal(2, v6mc.getsockopt(:IPPROTO_IPV6, :IPV6_MULTICAST_HOPS).int)
    end
  end

end

end
