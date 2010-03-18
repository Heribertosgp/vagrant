require File.join(File.dirname(__FILE__), '..', 'test_helper')

class EnvironmentTest < Test::Unit::TestCase
  setup do
    mock_config
  end

  context "paths" do
    setup do
      @env = mock_environment
    end

    context "cwd" do
      should "default to Dir.pwd" do
        assert_equal Dir.pwd, @env.cwd
      end

      should "return cwd if set" do
        @env.cwd = "foo"
        assert_equal "foo", @env.cwd
      end
    end

    context "dotfile path" do
      setup do
        @env.stubs(:root_path).returns("foo")
      end

      should "build up the dotfile out of the root path and the dotfile name" do
        assert_equal File.join(@env.root_path, @env.config.vagrant.dotfile_name), @env.dotfile_path
      end
    end
  end

  context "loading" do
    setup do
      @env = mock_environment
    end

    context "overall load method" do
      should "load! should load the config and set the persisted_uid" do
        call_seq = sequence("call_sequence")
        @env.expects(:load_root_path!).once.in_sequence(call_seq)
        @env.expects(:load_config!).once.in_sequence(call_seq)
        @env.expects(:load_home_directory!).once.in_sequence(call_seq)
        @env.expects(:load_box!).once.in_sequence(call_seq)
        @env.expects(:load_config!).once.in_sequence(call_seq)
        @env.expects(:load_vm!).once.in_sequence(call_seq)
        @env.load!
      end
    end

    context "loading the root path" do
      setup do
        @env.cwd = "/foo"
      end

      should "default the path to the cwd instance var if nil" do
        @path = mock("path")
        @path.stubs(:root?).returns(true)
        Pathname.expects(:new).with(@env.cwd).returns(@path)
        @env.load_root_path!(nil)
      end

      should "not default the path to pwd if its not nil" do
        @path = mock("path")
        @path.stubs(:to_s).returns("/")
        File.expects(:expand_path).with(@path).returns("/")
        Pathname.expects(:new).with("/").returns(@path)
        @path.stubs(:root?).returns(true)
        @env.load_root_path!(@path)
      end

      should "should walk the parent directories looking for rootfile" do
        paths = [
          Pathname.new("/foo/bar/baz"),
          Pathname.new("/foo/bar"),
          Pathname.new("/foo")
        ]

        search_seq = sequence("search_seq")
        paths.each do |path|
          File.expects(:exist?).with("#{path}/#{Vagrant::Environment::ROOTFILE_NAME}").returns(false).in_sequence(search_seq)
        end

        assert !@env.load_root_path!(paths.first)
      end

      should "return false if not found" do
        path = Pathname.new("/")
        assert !@env.load_root_path!(path)
      end

      should "return false if not found on windows-style root" do
        # TODO: Is there _any_ way to test this on unix machines? The
        # expand path doesn't work [properly for the test] on unix machines.
        if RUBY_PLATFORM.downcase.include?("mswin")
          # Note the escaped back slash
          path = Pathname.new("C:\\")
          assert !@env.load_root_path!(path)
        end
      end

      should "should set the path for the rootfile" do
        path = "/foo"
        File.expects(:exist?).with("#{path}/#{Vagrant::Env::ROOTFILE_NAME}").returns(true)

        assert Vagrant::Env.load_root_path!(Pathname.new(path))
        assert_equal path, Vagrant::Env.root_path
      end
    end

    context "loading config" do
      setup do
        @root_path = "/foo"
        @env = Vagrant::Environment.new
        @env.stubs(:root_path).returns(@root_path)

        File.stubs(:exist?).returns(false)
        Vagrant::Config.stubs(:execute!)
        Vagrant::Config.stubs(:reset!)
      end

      should "reset the configuration object" do
        Vagrant::Config.expects(:reset!).once
        @env.load_config!
      end

      should "load from the project root" do
        File.expects(:exist?).with(File.join(PROJECT_ROOT, "config", "default.rb")).once
        @env.load_config!
      end

      should "load from the root path" do
        File.expects(:exist?).with(File.join(@root_path, Vagrant::Environment::ROOTFILE_NAME)).once
        @env.load_config!
      end

      should "not load from the root path if nil" do
        @env.stubs(:root_path).returns(nil)
        File.expects(:exist?).with(File.join(@root_path, Vagrant::Environment::ROOTFILE_NAME)).never
        @env.load_config!
      end

      should "load the files only if exist? returns true" do
        File.expects(:exist?).once.returns(true)
        @env.expects(:load).once
        @env.load_config!
      end

      should "not load the files if exist? returns false" do
        @env.expects(:load).never
        @env.load_config!
      end

      should "execute after loading and set result to environment config" do
        result = mock("result")
        File.expects(:exist?).once.returns(true)
        @env.expects(:load).once
        Vagrant::Config.expects(:execute!).once.returns(result)
        @env.load_config!
        assert_equal result, @env.config
      end
    end

    context "loading home directory" do
      setup do
        @env = mock_environment
        @home_dir = File.expand_path(@env.config.vagrant.home)

        File.stubs(:directory?).returns(true)
        FileUtils.stubs(:mkdir_p)
      end

      should "create each directory if it doesn't exist" do
        create_seq = sequence("create_seq")
        File.stubs(:directory?).returns(false)
        Vagrant::Env::HOME_SUBDIRS.each do |subdir|
          FileUtils.expects(:mkdir_p).with(File.join(@home_dir, subdir)).in_sequence(create_seq)
        end

        @env.load_home_directory!
      end

      should "not create directories if they exist" do
        File.stubs(:directory?).returns(true)
        FileUtils.expects(:mkdir_p).never
        @env.load_home_directory!
      end
    end

    context "loading box" do
      setup do
        @box = mock("box")

        @env = mock_environment
        @env.stubs(:root_path).returns("foo")
      end

      should "do nothing if the root path is nil" do
        Vagrant::Box.expects(:find).never
        @env.stubs(:root_path).returns(nil)
        @env.load_box!
      end

      should "not load the box if its not set" do
        @env = mock_environment do |config|
          config.vm.box = nil
        end

        Vagrant::Box.expects(:find).never
        @env.load_box!
      end

      should "set the box to what is found by the Box class" do
        Vagrant::Box.expects(:find).with(@env.config.vm.box).once.returns(@box)
        @env.load_box!
        assert @box.equal?(@env.box)
      end
    end

    context "loading the UUID out from the persisted dotfile" do
      setup do
        @env = mock_environment
        @env.stubs(:root_path).returns("foo")

        File.stubs(:file?).returns(true)
      end

      should "loading of the uuid from the dotfile" do
        vm = mock("vm")

        filemock = mock("filemock")
        filemock.expects(:read).returns("foo")
        Vagrant::VM.expects(:find).with("foo").returns(vm)
        File.expects(:open).with(@env.dotfile_path).once.yields(filemock)
        File.expects(:file?).with(@env.dotfile_path).once.returns(true)
        @env.load_vm!

        assert_equal vm, @env.vm
      end

      should "do nothing if the root path is nil" do
        File.expects(:open).never
        @env.stubs(:root_path).returns(nil)
        @env.load_vm!
      end

      should "do nothing if dotfile is not a file" do
        File.expects(:file?).returns(false)
        File.expects(:open).never
        @env.load_vm!
      end

      should "uuid should be nil if dotfile didn't exist" do
        File.expects(:open).raises(Errno::ENOENT)
        @env.load_vm!
        assert_nil @env.vm
      end
    end
  end
end
