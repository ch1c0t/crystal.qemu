require "spec"
require "../../src/grml"

describe GRML::AlpineBundleRun do
  it "creates a UTC timestamped run directory and a relative LATEST value" do
    timestamp = Time.utc(2026, 11, 14, 12, 29, 0)
    run = GRML::AlpineBundleRun.new(
      "latest-stable",
      "/home/om/shared/",
      timestamp,
      123_i64
    )

    run.run_id.should eq("latest-stable-20261114T122900Z-7b")
    run.directory.should eq("/mnt/shared/alpine-bundles/runs/latest-stable-20261114T122900Z-7b")
    run.host_directory.should eq("/home/om/shared/alpine-bundles/runs/latest-stable-20261114T122900Z-7b")
    run.host_latest_pointer.should eq("/home/om/shared/alpine-bundles/LATEST")
    run.latest_pointer_contents.should eq("runs/latest-stable-20261114T122900Z-7b")
  end

  it "keeps the APK repository root separate from its architecture directory" do
    run = GRML::AlpineBundleRun.new(
      "v3.24",
      "/shared",
      Time.utc(2026, 11, 14, 12, 29, 0),
      456_i64
    )

    run.repository_root.should eq("#{run.directory}/repository")
    run.packages_directory.should eq("#{run.repository_root}/x86_64")
  end

  it "creates different run paths for distinct nonce values in the same second" do
    timestamp = Time.utc(2026, 11, 14, 12, 29, 0)
    first = GRML::AlpineBundleRun.new("latest-stable", "/shared", timestamp, 1_i64)
    second = GRML::AlpineBundleRun.new("latest-stable", "/shared", timestamp, 2_i64)

    first.directory.should_not eq(second.directory)
  end

  it "rejects unsafe branch names" do
    expect_raises(ArgumentError, "Invalid Alpine branch") do
      GRML::AlpineBundleRun.new(
        "v3.24; touch /tmp/pwned",
        "/shared",
        Time.utc(2026, 11, 14),
        1_i64
      )
    end
  end

  it "rejects negative run nonces" do
    expect_raises(ArgumentError, "nonce must not be negative") do
      GRML::AlpineBundleRun.new(
        "latest-stable",
        "/shared",
        Time.utc(2026, 11, 14),
        -1_i64
      )
    end
  end
  it "rewrites every indexed package architecture to match its repository directory" do
    run = GRML::AlpineBundleRun.new(
      "latest-stable",
      "/shared",
      Time.utc(2026, 11, 14, 12, 29, 0),
      123_i64
    )

    command = run.repository_index_command
    command.should contain("index --rewrite-arch x86_64")
    command.should contain("#{run.packages_directory}/APKINDEX.tar.gz")
    command.should contain("'#{run.packages_directory}'")
  end

end
