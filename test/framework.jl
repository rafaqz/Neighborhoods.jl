using DynamicGrids, Test, Setfield
import DynamicGrids: applyrule, applyrule!, maprule!, 
       source, dest, currenttime, getdata, combinedata, ruleloop,
       SimData, WritableGridData, _Read_, _Write_

init  = [0 1 1 0;
         0 1 1 0;
         0 1 1 0;
         0 1 1 0;
         0 1 1 0]

struct TestRule{R,W} <: Rule{R,W} end
applyrule(::TestRule, data, state, index) = 0

@testset "Must include init" begin
    output = ArrayOutput(init, 7)
    ruleset = Ruleset()
    @test_throws ArgumentError sim!(output, ruleset)
end

@testset "a rule that returns zero gives zero outputs" begin
    final = [0 0 0 0;
             0 0 0 0;
             0 0 0 0;
             0 0 0 0;
             0 0 0 0]

    rule = TestRule()
    ruleset = Ruleset(rule; init=init)

    @test DynamicGrids.init(ruleset) === init
    @test DynamicGrids.mask(ruleset) === nothing
    @test DynamicGrids.overflow(ruleset) === RemoveOverflow()
    @test DynamicGrids.opt(ruleset) === SparseOpt()
    @test DynamicGrids.cellsize(ruleset) === 1
    @test DynamicGrids.timestep(ruleset) === 1
    @test DynamicGrids.ruleset(ruleset) === ruleset

    simdata = SimData(init, ruleset, 1)

    # Test maprules components
    rkeys, rdata = getdata(_Read_(), rule, simdata)
    wkeys, wdata = getdata(_Write_(), rule, simdata)
    @test rkeys == Val{:_default_}()
    @test wkeys == Val{:_default_}()
    newsimdata = @set simdata.data = combinedata(rkeys, rdata, wkeys, wdata)
    @test newsimdata.data[1] isa WritableGridData
    # Test type stability
    @inferred ruleloop(NoOpt(), rule, newsimdata, rkeys, rdata, wkeys, wdata)
    
    resultdata = maprule!(simdata, rule)
    @test source(resultdata[:_default_]) == final
end

struct TestPartial{R,W} <: PartialRule{R,W} end
applyrule!(::TestPartial, data, state, index) = 0

@testset "a partial rule that returns zero does nothing" begin
    rule = TestPartial()
    ruleset = Ruleset(rule; init=init)
    # Test type stability
    simdata = SimData(init, ruleset, 1)
    rkeys, rdata = getdata(_Read_(), rule, simdata)
    wkeys, wdata = getdata(_Write_(), rule, simdata)
    newsimdata = @set simdata.data = combinedata(wkeys, wdata, rkeys, rdata)

    @inferred ruleloop(NoOpt(), rule, newsimdata, rkeys, rdata, wkeys, wdata)

    resultdata = maprule!(simdata, rule)
    @test source(resultdata[:_default_]) == init
end

struct TestPartialWrite{R,W} <: PartialRule{R,W} end
applyrule!(::TestPartialWrite, data, state, index) = data[:_default_][index[1], 2] = 0

@testset "a partial rule that writes to dest affects output" begin
    final = [0 0 1 0;
             0 0 1 0;
             0 0 1 0;
             0 0 1 0;
             0 0 1 0]

    rule = TestPartialWrite()
    ruleset = Ruleset(rule; init=init)
    simdata = SimData(init, ruleset, 1)
    resultdata = maprule!(simdata, rule)
    @test source(first(resultdata)) == final
end

struct TestCellTriple{R,W} <: CellRule{R,W} end
applyrule(::TestCellTriple, data, state, index) = 3state

struct TestCellSquare{R,W} <: CellRule{R,W} end
applyrule(::TestCellSquare, data, (state,), index) = state^2

@testset "a chained cell rull" begin
    init  = [0 1 2 3;
             4 5 6 7]

    final = [0 9 36 81;
             144 225 324 441]
    rule = Chain(TestCellTriple(), 
                 TestCellSquare())
    ruleset = Ruleset(rule; init=init)
    simdata = SimData(init, ruleset, 1)
    resultdata = maprule!(simdata, ruleset.rules[1]);
    @test source(first(resultdata)) == final
end

struct PrecalcRule{R,W,P} <: Rule{R,W}
    precalc::P
end
DynamicGrids.precalcrules(rule::PrecalcRule, data) = 
    PrecalcRule(currenttime(data))
applyrule(rule::PrecalcRule, data, state, index) = rule.precalc[]

@testset "a rule with precalculations" begin
    init  = [1 1;
             1 1]

    out2  = [2 2;
             2 2]

    out3  = [3 3;
             3 3]

    rule = PrecalcRule(1)
    ruleset = Ruleset(rule; init=init)
    output = ArrayOutput(init, 3)
    sim!(output, ruleset; tspan=(1, 3))
    @test output[2] == out2
    @test output[3] == out3
end


