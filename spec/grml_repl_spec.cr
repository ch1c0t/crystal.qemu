require "spec"
require "../src/logger"
require "../src/grml"

struct FakeGRMLOCRResult
  getter text : String
  getter error : String?
  getter timestamp : Int64

  def initialize(@text : String = "", @error : String? = nil, @timestamp : Int64 = 0_i64)
  end
end

class FakeGRMLInteraction
  def latest_ocr : FakeGRMLOCRResult
    FakeGRMLOCRResult.new
  end
end

class FakeGRMLAgent
  getter interaction : FakeGRMLInteraction
  getter prepared_branches = [] of String

  def initialize
    @interaction = FakeGRMLInteraction.new
  end

  def prepare_alpine_bundle(branch : String = "latest-stable") : Nil
    @prepared_branches << branch
  end
end

def with_grml_repl_focus(value : String?, &block : -> T) : T forall T
  previous = ENV[GRML::REPL::FOCUS_ENV]?

  if value
    ENV[GRML::REPL::FOCUS_ENV] = value
  else
    ENV.delete(GRML::REPL::FOCUS_ENV)
  end

  yield
ensure
  if previous
    ENV[GRML::REPL::FOCUS_ENV] = previous
  else
    ENV.delete(GRML::REPL::FOCUS_ENV)
  end
end

describe GRML::REPL do
  it "focuses the REPL by default" do
    with_grml_repl_focus(nil) do
      GRML::REPL.focus?.should be_true
    end
  end

  it "accepts common true values" do
    {"true", "TRUE", "yes", "on", "1"}.each do |value|
      with_grml_repl_focus(value) do
        GRML::REPL.focus?.should be_true
      end
    end
  end

  it "accepts common false values" do
    {"false", "FALSE", "no", "off", "0"}.each do |value|
      with_grml_repl_focus(value) do
        GRML::REPL.focus?.should be_false
      end
    end
  end

  it "rejects invalid focus values" do
    with_grml_repl_focus("sometimes") do
      expect_raises(ArgumentError, "GRML_AGENT_REPL_FOCUS") do
        GRML::REPL.focus?
      end
    end
  end

  it "registers both custom commands" do
    definition = GRML::REPL.build_definition(FakeGRMLAgent.new)
    definition.command_names.should eq(["ocr", "prepare_alpine_bundle"])
  end

  it "defaults bundle preparation to latest-stable" do
    agent = FakeGRMLAgent.new

    result = GRML::REPL.prepare_alpine_bundle(agent, [] of String)

    result.should contain("latest-stable")
    agent.prepared_branches.should eq(["latest-stable"])
  end

  it "can prepare the bundle repeatedly using the same booted agent" do
    agent = FakeGRMLAgent.new

    GRML::REPL.prepare_alpine_bundle(agent, [] of String)
    GRML::REPL.prepare_alpine_bundle(agent, ["v3.24"])

    agent.prepared_branches.should eq(["latest-stable", "v3.24"])
  end

  it "rejects multiple branch arguments" do
    agent = FakeGRMLAgent.new

    expect_raises(ArgumentError, "Usage: prepare_alpine_bundle") do
      GRML::REPL.prepare_alpine_bundle(agent, ["v3.24", "v3.25"])
    end

    agent.prepared_branches.should be_empty
  end

  it "rejects unsafe branch names" do
    agent = FakeGRMLAgent.new

    expect_raises(ArgumentError, "Invalid Alpine branch") do
      GRML::REPL.prepare_alpine_bundle(agent, ["v3.24; touch /tmp/pwned"])
    end

    agent.prepared_branches.should be_empty
  end
end
