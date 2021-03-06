%%
%% %CopyrightBegin%
%% 
%% Copyright Ericsson AB 1996-2009. All Rights Reserved.
%% 
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%% 
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%% 
%% %CopyrightEnd%
%%
-module(erl_prim_loader_SUITE).

-include_lib("kernel/include/file.hrl").
-include("test_server.hrl").

-export([all/1]).

-export([get_path/1, set_path/1, get_file/1,
	 inet_existing/1, inet_coming_up/1, inet_disconnects/1,
	 multiple_slaves/1, file_requests/1,
	 local_archive/1, remote_archive/1,
	 primary_archive/1]).

-export([init_per_testcase/2, fin_per_testcase/2]).

%%-----------------------------------------------------------------
%% Test suite for erl_prim_loader. (Most code is run during system start/stop.)
%%-----------------------------------------------------------------

all(suite) ->
    [
     get_path, set_path, get_file,
     inet_existing, inet_coming_up,
     inet_disconnects, multiple_slaves,
     file_requests, local_archive, 
     remote_archive, primary_archive
    ].

init_per_testcase(Func, Config) when atom(Func), list(Config) ->
    Dog=?t:timetrap(?t:minutes(3)),
    [{watchdog, Dog}|Config].

fin_per_testcase(_Func, Config) ->
    Dog=?config(watchdog, Config),
    ?t:timetrap_cancel(Dog).

get_path(doc) -> [];
get_path(Config) when is_list(Config) ->
    ?line case erl_prim_loader:get_path() of
	      {ok, Path} when is_list(Path) ->
		  ok;
	      _ ->
		  test_server:fail(get_path)
	  end,
    ok.

set_path(doc) -> [];
set_path(Config) when is_list(Config) ->
    ?line {ok, Path} = erl_prim_loader:get_path(),
    ?line ok = erl_prim_loader:set_path(Path),
    ?line {ok, Path} = erl_prim_loader:get_path(),
    NewPath = Path ++ ["dummy_dir","/dummy_dir/dummy_dir"],
    ?line ok = erl_prim_loader:set_path(NewPath),
    ?line {ok, NewPath} = erl_prim_loader:get_path(),

    ?line ok = erl_prim_loader:set_path(Path), % Reset path.
    ?line {ok, Path} = erl_prim_loader:get_path(),

    ?line {'EXIT',_} = (catch erl_prim_loader:set_path(not_a_list)),
    ?line {ok, Path} = erl_prim_loader:get_path(),
    ok.

get_file(doc) -> [];
get_file(Config) when is_list(Config) ->
    ?line case erl_prim_loader:get_file("lists" ++ code:objfile_extension()) of
	      {ok,Bin,File} when binary(Bin), list(File) ->
		  ok;
	      _ ->
		  test_server:fail(get_valid_file)
	  end,
    ?line error = erl_prim_loader:get_file("duuuuuuummmy_file"),
    ?line error = erl_prim_loader:get_file(duuuuuuummmy_file),
    ?line error = erl_prim_loader:get_file({dummy}),
    ok.

inet_existing(doc) -> ["Start a node using the 'inet' loading method, ",
		       "from an already started boot server."];
inet_existing(Config) when is_list(Config) ->
    case os:type() of
	vxworks ->
	    {comment, "VxWorks: tested separately"};
	_ ->
	    ?line Name = erl_prim_test_inet_existing,
	    ?line Host = host(),
	    ?line Cookie = atom_to_list(erlang:get_cookie()),
	    ?line IpStr = ip_str(Host),
	    ?line LFlag = get_loader_flag(os:type()),
	    ?line Args = LFlag ++ " -hosts " ++ IpStr ++
		" -setcookie " ++ Cookie,
	    ?line {ok, BootPid} = erl_boot_server:start_link([Host]),
	    ?line {ok, Node} = start_node(Name, Args),
	    ?line {ok,[["inet"]]} = rpc:call(Node, init, get_argument, [loader]),
	    ?line stop_node(Node),
	    ?line unlink(BootPid),
	    ?line exit(BootPid, kill),
	    ok
    end.

inet_coming_up(doc) -> ["Start a node using the 'inet' loading method, ",
			"but start the boot server afterwards."];
inet_coming_up(Config) when is_list(Config) ->
    case os:type() of
	vxworks ->
	    {comment, "VxWorks: tested separately"};
	_ ->
	    ?line Name = erl_prim_test_inet_coming_up,
	    ?line Cookie = atom_to_list(erlang:get_cookie()),
	    ?line Host = host(),
	    ?line IpStr = ip_str(Host),
	    ?line LFlag = get_loader_flag(os:type()),
	    ?line Args = LFlag ++ 
		" -hosts " ++ IpStr ++
		" -setcookie " ++ Cookie,
	    ?line {ok, Node} = start_node(Name, Args, [{wait, false}]),

	    %% Wait a while, then start boot server, and wait for node to start.
	    ?line test_server:sleep(test_server:seconds(6)),
	    io:format("erl_boot_server:start_link([~p]).", [Host]),
	    ?line {ok, BootPid} = erl_boot_server:start_link([Host]),
	    ?line wait_really_started(Node, 25),

	    %% Check loader argument, then cleanup.
	    ?line {ok,[["inet"]]} = rpc:call(Node, init, get_argument, [loader]),
	    ?line stop_node(Node),
	    ?line unlink(BootPid),
	    ?line exit(BootPid, kill),
	    ok
    end.

wait_really_started(Node, 0) ->
    test_server:fail({not_booted,Node});
wait_really_started(Node, N) ->
    case rpc:call(Node, init, get_status, []) of
 	{started, _} ->
 	    ok;
	_ ->
	    test_server:sleep(1000),
 	    wait_really_started(Node, N - 1)
    end.

inet_disconnects(doc) -> ["Start a node using the 'inet' loading method, ",
			  "then lose the connection."];
inet_disconnects(Config) when is_list(Config) ->
    case os:type() of
	vxworks ->
	    {comment, "VxWorks: tested separately"};
	_ ->
	    ?line Name = erl_prim_test_inet_disconnects,
	    ?line Host = host(),
	    ?line Cookie = atom_to_list(erlang:get_cookie()),
	    ?line IpStr = ip_str(Host),
	    ?line LFlag = get_loader_flag(os:type()),
	    ?line Args = LFlag ++ " -hosts " ++ IpStr ++
		" -setcookie " ++ Cookie,
	    
	    ?line {ok, BootPid} = erl_boot_server:start([Host]),
	    Self = self(),
	    %% This process shuts down the boot server during loading.
	    ?line Stopper = spawn_link(fun() -> stop_boot(BootPid, Self) end),
	    ?line receive
		      {Stopper,ready} -> ok
		  end,

	    %% Let the loading begin...
	    ?line {ok, Node} = start_node(Name, Args, [{wait, false}]),

	    %% When the stopper is ready, the slave node should be
	    %% looking for a boot server again.
	    receive 
		{Stopper,ok} -> 
		    ok;
		{Stopper,{error,Reason}} ->
		    ?line ?t:fail(Reason)
	    after 60000 -> 
		    ?line ?t:fail(stopper_died)
	    end,

	    %% Start new boot server to see that loading is continued.
	    ?line {ok, BootPid2} = erl_boot_server:start_link([Host]),
	    ?line wait_really_started(Node, 25),
	    ?line {ok,[["inet"]]} = rpc:call(Node, init, get_argument, [loader]),
	    ?line stop_node(Node),
	    ?line unlink(BootPid2),
	    ?line exit(BootPid2, kill),
	    ok
    end.

%% Trace boot server calls and stop the server before loading is finished.
stop_boot(BootPid, Super) ->
    erlang:trace(all, true, [call]),
    1 = erlang:trace_pattern({erl_boot_server,send_file_result,3}, true, [local]),
    BootRef = erlang:monitor(process, BootPid),
    Super ! {self(),ready},
    Result = get_calls(100, BootPid),
    exit(BootPid, kill),
    erlang:trace_pattern({erl_boot_server,send_file_result,3}, false, [local]),
    erlang:trace(all, false, [call]),
    receive
	{'DOWN',BootRef,_,_, killed} -> ok
    end,
    Super ! {self(),Result}.    

get_calls(0, _) ->
    ok;
get_calls(Count, Pid) ->
    receive
	{trace,_,call,_MFA} ->
	    get_calls(Count-1, Pid)
    after 10000 ->
	    {error,{trace_msg_timeout,Count}}
    end.	

multiple_slaves(doc) ->
    ["Start nodes in parallell, all using the 'inet' loading method, ",
     "verify that the boot server manages"];
multiple_slaves(Config) when is_list(Config) ->
    case os:type() of
	vxworks ->
	    {comment, "VxWorks: tested separately"};
	{ose,_} ->
	    {comment, "OSE: multiple nodes not supported"};
	_ ->
	    ?line Name = erl_prim_test_multiple_slaves,
	    ?line Host = host(),
	    ?line Cookie = atom_to_list(erlang:get_cookie()),
	    ?line IpStr = ip_str(Host),
	    ?line LFlag = get_loader_flag(os:type()),
	    ?line Args = LFlag ++ " -hosts " ++ IpStr ++
		" -setcookie " ++ Cookie,

	    NoOfNodes = 10,			% no of slave nodes to be started

	    NamesAndNodes = 
		lists:map(fun(N) ->
				  NameN = atom_to_list(Name) ++ 
				          integer_to_list(N),
				  NodeN = NameN ++ "@" ++ Host,
				  {list_to_atom(NameN),list_to_atom(NodeN)}
			  end, lists:seq(1, NoOfNodes)),

	    ?line Nodes = start_multiple_nodes(NamesAndNodes, Args, []),

	    %% "queue up" the nodes to wait for the boot server to respond
	    %% (note: test_server supervises each node start by accept()
	    %% on a socket, the timeout value for the accept has to be quite 
	    %% long for this test to work).
	    ?line test_server:sleep(test_server:seconds(5)),
	    %% start the code loading circus!
	    ?line {ok,BootPid} = erl_boot_server:start_link([Host]),
	    %% give the nodes a chance to boot up before attempting to stop them
	    ?line test_server:sleep(test_server:seconds(10)),

	    ?line wait_and_shutdown(lists:reverse(Nodes), 30),

	    ?line unlink(BootPid),
	    ?line exit(BootPid, kill),
	    ok
    end.

start_multiple_nodes([{Name,Node} | NNs], Args, Started) ->
    ?line {ok,Node} = start_node(Name, Args, [{wait, false}]),
    start_multiple_nodes(NNs, Args, [Node | Started]);
start_multiple_nodes([], _, Nodes) ->
    Nodes.

wait_and_shutdown([Node | Nodes], Tries) ->
    ?line wait_really_started(Node, Tries),
    ?line {ok,[["inet"]]} = rpc:call(Node, init, get_argument, [loader]),
    ?line stop_node(Node),
    wait_and_shutdown(Nodes, Tries);
wait_and_shutdown([], _) ->
    ok.


file_requests(suite) -> {req, [{local_slave_nodes, 1}, {time, 10}]};
file_requests(doc) -> ["Start a node using the 'inet' loading method, ",
		       "verify that the boot server responds to file requests."];
file_requests(Config) when is_list(Config) ->
    ?line {ok, Node, BootPid} = complete_start_node(erl_prim_test_file_req),

    %% compare with results from file server calls (the
    %% boot server uses the same file sys and cwd)
    {ok,Files} = file:list_dir("."),
    ?line {ok,Files} = rpc:call(Node, erl_prim_loader, list_dir, ["."]),
    {ok,Info} = file:read_file_info("test_server.beam"),
    ?line {ok,Info} = rpc:call(Node, erl_prim_loader, read_file_info, ["test_server.beam"]),
    {ok,Cwd} = file:get_cwd(),
    ?line {ok,Cwd} = rpc:call(Node, erl_prim_loader, get_cwd, []),
    case file:get_cwd("C:") of
	{error,enotsup} ->
	    ok;
	{ok,DCwd} ->
	    ?line {ok,DCwd} = rpc:call(Node, erl_prim_loader, get_cwd, ["C:"])
    end,

    ?line stop_node(Node),
    ?line unlink(BootPid),
    ?line exit(BootPid, kill),
    ok.

complete_start_node(Name) ->
    ?line Host = host(),
    ?line Cookie = atom_to_list(erlang:get_cookie()),
    ?line IpStr = ip_str(Host),
    ?line LFlag = get_loader_flag(os:type()),
    ?line Args = LFlag ++ " -hosts " ++ IpStr ++
	" -setcookie " ++ Cookie,

    ?line {ok,BootPid} = erl_boot_server:start_link([Host]),

    ?line {ok,Node} = start_node(Name, Args),
    ?line wait_really_started(Node, 25),
    {ok, Node, BootPid}.

local_archive(suite) ->
    [];
local_archive(doc) ->
    ["Read files from local archive."];
local_archive(Config) when is_list(Config) ->
    PrivDir = ?config(priv_dir, Config),
    KernelDir = filename:basename(code:lib_dir(kernel)),
    Archive = filename:join([PrivDir, KernelDir ++ init:archive_extension()]),
    file:delete(Archive),
    ?line {ok, Archive} = create_archive(Archive, [KernelDir]),

    Node = node(),
    BeamName = "inet.beam",
    ?line ok = test_archive(Node, Archive, KernelDir, BeamName),
    ?line ok = rpc:call(Node, erl_prim_loader, release_archives, []),

    ?line ok = file:delete(Archive),
    ok.

remote_archive(suite) ->
    {req, [{local_slave_nodes, 1}, {time, 10}]};
remote_archive(doc) ->
    ["Read files from remote archive."];
remote_archive(Config) when is_list(Config) ->
    PrivDir = ?config(priv_dir, Config),
    KernelDir = filename:basename(code:lib_dir(kernel)),
    Archive = filename:join([PrivDir, KernelDir ++ init:archive_extension()]),
    file:delete(Archive),
    ?line {ok, Archive} = create_archive(Archive, [KernelDir]), 

    ?line {ok, Node, BootPid} = complete_start_node(remote_archive),

    BeamName = "inet.beam",
    ?line ok = test_archive(Node, Archive, KernelDir, BeamName),

    ?line stop_node(Node),
    ?line unlink(BootPid),
    ?line exit(BootPid, kill),
    ok.

primary_archive(suite) ->
    {req, [{local_slave_nodes, 1}, {time, 10}]};
primary_archive(doc) ->
    ["Read files from primary archive."];
primary_archive(Config) when is_list(Config) ->
    %% Copy the orig files to priv_dir
    PrivDir = ?config(priv_dir, Config),
    Archive = filename:join([PrivDir, "primary_archive.zip"]),
    file:delete(Archive),
    DataDir = ?config(data_dir, Config),
    ?line {ok, _} = zip:create(Archive, ["primary_archive"],
			       [{compress, []}, {cwd, DataDir}]),
    ?line {ok, _} = zip:extract(Archive, [{cwd, PrivDir}]),
    TopDir = filename:join([PrivDir, "primary_archive"]),

    %% Compile the code
    DictDir = "primary_archive_dict-1.0",
    DummyDir = "primary_archive_dummy",
    ?line ok = compile_app(TopDir, DictDir),
    ?line ok = compile_app(TopDir, DummyDir),
    
    %% Create the archive
    {ok, TopFiles} = file:list_dir(TopDir),
    ?line {ok, {_, ArchiveBin}} = zip:create(Archive, TopFiles,
					     [memory, {compress, []}, {cwd, TopDir}]),
    
    %% Use temporary node to simplify cleanup
    ?line Cookie = atom_to_list(erlang:get_cookie()),
    ?line Args = " -setcookie " ++ Cookie,
    ?line {ok,Node} = start_node(primary_archive, Args),
    ?line wait_really_started(Node, 25),

    %% Set primary archive 
    ?line {_,_,_} = rpc:call(Node, erlang, date, []),
    ?line {ok, Ebins} = rpc:call(Node, erl_prim_loader, set_primary_archive, [Archive, ArchiveBin]),
    ExpectedEbins = [Archive, DictDir ++ "/ebin", DummyDir ++ "/ebin"],
    io:format("ExpectedEbins: ~p\n", [ExpectedEbins]),
    ?line ExpectedEbins = lists:sort(Ebins),
    
    ?line {ok, TopFiles2} = rpc:call(Node, erl_prim_loader, list_dir, [Archive]),
    ?line [DictDir, DummyDir] = lists:sort(TopFiles2),
    BeamName = "primary_archive_dict_app.beam",
    ?line ok = test_archive(Node, Archive, DictDir, BeamName),
    
    ?line {ok, []} = rpc:call(Node, erl_prim_loader, set_primary_archive, [undefined, undefined]),

    ?line stop_node(Node),
    ?line ok = file:delete(Archive),
    ok.

test_archive(Node, TopDir, AppDir, BeamName) ->
    %% List dir
    io:format("test_archive: ~p\n", [rpc:call(Node, erl_prim_loader, list_dir, [TopDir])]),
    ?line {ok, TopFiles} = rpc:call(Node, erl_prim_loader, list_dir, [TopDir]),
    ?line true = lists:member(AppDir, TopFiles),
    AbsAppDir = TopDir ++ "/" ++ AppDir,
    ?line {ok, AppFiles} = rpc:call(Node, erl_prim_loader, list_dir, [AbsAppDir]),
    ?line true = lists:member("ebin", AppFiles),
    Ebin = AbsAppDir ++ "/ebin",
    ?line {ok, EbinFiles} = rpc:call(Node, erl_prim_loader, list_dir, [Ebin]),
    Beam = Ebin ++ "/" ++ BeamName,
    ?line true = lists:member(BeamName, EbinFiles),
    ?line error = rpc:call(Node, erl_prim_loader, list_dir, [TopDir ++ "/no_such_file"]),
    ?line error = rpc:call(Node, erl_prim_loader, list_dir, [TopDir ++ "/ebin/no_such_file"]),
    
    %% File info
    ?line {ok, #file_info{type = directory}} =
	rpc:call(Node, erl_prim_loader, read_file_info, [TopDir]),
    ?line {ok, #file_info{type = directory}} =
	rpc:call(Node, erl_prim_loader, read_file_info, [Ebin]),
    ?line {ok, #file_info{type = regular} = FI}  =
	rpc:call(Node, erl_prim_loader, read_file_info, [Beam]),
    ?line error = rpc:call(Node, erl_prim_loader, read_file_info, [TopDir ++ "/no_such_file"]),
    ?line error = rpc:call(Node, erl_prim_loader, read_file_info, [TopDir ++ "/ebin/no_such_file"]),
    
    %% Get file
    ?line {ok, Bin, Beam} = rpc:call(Node, erl_prim_loader, get_file, [Beam]),
    ?line if
	      FI#file_info.size =:= byte_size(Bin) -> ok;
	      true -> exit({FI#file_info.size, byte_size(Bin)})
	  end,
    ?line error = rpc:call(Node, erl_prim_loader, get_file, ["/no_such_file"]),
    ?line error = rpc:call(Node, erl_prim_loader, get_file, ["/ebin/no_such_file"]),
    ok.

create_archive(Archive, AppDirs) ->
    LibDir = code:lib_dir(),
    Opts = [{compress, []}, {cwd, LibDir}],
    io:format("zip:create(~p,\n\t~p,\n\t~p).\n", [Archive, AppDirs, Opts]),
    zip:create(Archive, AppDirs, Opts).

%% Misc. functions

ip_str({A, B, C, D}) ->
    lists:concat([A, ".", B, ".", C, ".", D]);
ip_str(Host) ->
    {ok,Ip} = inet:getaddr(Host, inet),
    ip_str(Ip).

start_node(Name, Args) ->
    start_node(Name, Args, []).

start_node(Name, Args, Opts) ->
    Opts2 = [{args, Args}|Opts],
    io:format("test_server:start_node(~p, peer, ~p).\n",
	      [Name, Opts2]),
    Res = test_server:start_node(Name, peer, Opts2),
    io:format("start_node -> ~p\n", [Res]),
    Res.

host() ->
    {ok,Host} = inet:gethostname(),
    Host.

stop_node(Node) ->
    test_server:stop_node(Node).

get_loader_flag({ose,_}) ->
    " -loader ose_inet ";
get_loader_flag(_) ->
    " -loader inet ".

compile_app(TopDir, AppName) ->
    AppDir = filename:join([TopDir, AppName]),
    SrcDir = filename:join([AppDir, "src"]),
    OutDir = filename:join([AppDir, "ebin"]),
    ?line {ok, Files} = file:list_dir(SrcDir),
    compile_files(Files, SrcDir, OutDir).

compile_files([File | Files], SrcDir, OutDir) ->
    case filename:extension(File) of
	".erl" ->
	    AbsFile = filename:join([SrcDir, File]),
	    case compile:file(AbsFile, [{outdir, OutDir}]) of
		{ok, _Mod} ->
		    compile_files(Files, SrcDir, OutDir);
		Error ->
		    {compilation_error, AbsFile, OutDir, Error}
	    end;
	_ ->
	    compile_files(Files, SrcDir, OutDir)
    end;
compile_files([], _, _) ->
    ok.

