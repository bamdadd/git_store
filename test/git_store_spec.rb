require 'git_store'

describe GitStore do

  REPO = File.expand_path(File.dirname(__FILE__) + '/repo')

  before do
    FileUtils.rm_rf REPO
    Dir.mkdir REPO
    Dir.chdir REPO
  end

  def store
    @store
  end
  
  def file(file, data)
    FileUtils.mkpath(File.dirname(file))
    open(file, 'w') { |io| io << data }
    if @use_git
      `git add #{file}`
      `git commit -m 'added #{file}'`
      File.unlink(file)
    end
  end

  def self.it(text, &block)
    super "#{text} with git" do
      `git init`
      @use_git = true
      @store = GitStore.new(REPO)
      instance_eval(&block)
    end
    
    super "#{text} without git" do
      @use_git = false
      @store = GitStore::FileStore.new(REPO)
      instance_eval(&block)
    end
  end

  it 'should have a head commit' do
    next unless @use_git
    
    file 'a', 'Hello'

    store.read_head.should_not be_nil
    File.should be_exist(store.object_path(store.read_head))
  end

  it 'should detect changes' do
    next unless @use_git

    file 'a', 'Hello'

    store.should be_changed
  end

  it 'should find modified entries' do
    store['a'] = 'Hello'

    store.root.should be_modified
    store.root.table['a'].should be_modified

    store.commit

    store['a'] = 'Bello'

    store.root.table['a'].should be_modified
  end

  it 'should load a repo' do
    file 'a', 'Hello'
    file 'b', 'World'
   
    store.load

    store['a'].should == 'Hello'
    store['b'].should == 'World'
  end

  it 'should rollback a transaction' do
    next if not @use_git
    
    file 'a/b', 'Hello'
    file 'c/d', 'World'

    begin
      store.transaction do
        store['a/b'] = 'Changed'
        store['x/a'] = 'Added'
        raise
      end
    rescue
    end

    store['a/b'].should == 'Hello'
    store['c/d'].should == 'World'
    store['x/a'].should be_nil
  end

  it 'should commit a transaction' do
    next if not @use_git
    
    file 'a/b', 'Hello'
    file 'c/d', 'World'

    store.transaction do
      store['a/b'] = 'Changed'
      store['x/a'] = 'Added'
    end

    store.load
    
    store['a/b'].should == 'Changed'
    store['c/d'].should == 'World'
    store['x/a'].should == 'Added'
  end

  it 'should allow only one transaction' do
    next if not @use_git
    
    file 'a/b', 'Hello'

    ready = false

    store.transaction do
      Thread.start do
        store.transaction do
          store['a/b'] = 'Changed by second thread'
        end
        ready = true
      end
      store['a/b'] = 'Changed'
    end
    
    sleep 0.01 until ready

    store.load
    
    store['a/b'].should == 'Changed by second thread'
  end

  it 'should load folders' do
    file 'x/a', 'Hello'
    file 'y/b', 'World'
    
    store.load
    store['x'].should be_kind_of(GitStore::Tree)
    store['y'].should be_kind_of(GitStore::Tree)

    store['x']['a'].should == 'Hello'
    store['y']['b'].should == 'World'
  end

  it 'should commit added files' do
    next if not @use_git
    
    store.load
    store['c'] = 'Hello'
    store['d'] = 'World'
    store.commit

    `git checkout`

    File.should be_exist('c')
    File.should be_exist('d')

    File.read('c').should == 'Hello'
    File.read('d').should == 'World'
  end

  it 'should load yaml' do
    file 'x/a.yml', '[1, 2, 3, 4]'

    store.load
    
    store['x']['a.yml'].should == [1,2,3,4]    
    store['x']['a.yml'] = [1,2,3,4,5]
  end

  it 'should resolv paths' do
    file 'x/a', 'Hello'
    file 'y/b', 'World'
    
    store.load
    
    store['x/a'].should == 'Hello'
    store['y/b'].should == 'World'

    store['y/b'] = 'Now this'

    store['y']['b'].should == 'Now this'        
  end

  it 'should create new trees' do
    store['new/tree'] = 'This tree'
    store['this', 'tree'] = 'Another'    
    store['new/tree'].should == 'This tree'
    store['this/tree'].should == 'Another'
  end

  it 'should delete entries' do
    store['a'] = 'Hello'
    store.delete('a')
    
    store['a'].should be_nil
  end

end
