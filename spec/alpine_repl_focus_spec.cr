require "spec"
require "../src/logger"
require "../src/alpine"

def with_alpine_repl_focus(value : String?, &block : -> T) : T forall T
  previous = ENV[Alpine::REPL::FOCUS_ENV]?

  if value
    ENV[Alpine::REPL::FOCUS_ENV] = value
  else
    ENV.delete(Alpine::REPL::FOCUS_ENV)
  end

  yield
ensure
  if previous
    ENV[Alpine::REPL::FOCUS_ENV] = previous
  else
    ENV.delete(Alpine::REPL::FOCUS_ENV)
  end
end

describe Alpine::REPL do
  it "focuses the REPL by default" do
    with_alpine_repl_focus(nil) do
      Alpine::REPL.focus?.should be_true
    end
  end

  it "accepts common true values" do
    {"true", "TRUE", "yes", "on", "1"}.each do |value|
      with_alpine_repl_focus(value) do
        Alpine::REPL.focus?.should be_true
      end
    end
  end

  it "accepts common false values" do
    {"false", "FALSE", "no", "off", "0"}.each do |value|
      with_alpine_repl_focus(value) do
        Alpine::REPL.focus?.should be_false
      end
    end
  end

  it "rejects invalid values instead of silently choosing a focus mode" do
    with_alpine_repl_focus("sometimes") do
      expect_raises(ArgumentError, "ALPINE_AGENT_REPL_FOCUS") do
        Alpine::REPL.focus?
      end
    end
  end
end
