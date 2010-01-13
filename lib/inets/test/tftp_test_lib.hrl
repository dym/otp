%%
%% %CopyrightBegin%
%% 
%% Copyright Ericsson AB 2007-2009. All Rights Reserved.
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

-record('REASON', {mod, line, desc}).

-define(LOG(Format, Args),
	tftp_test_lib:log(Format, Args, ?MODULE, ?LINE)).

-define(ERROR(Reason),
	tftp_test_lib:error(Reason, ?MODULE, ?LINE)).

-define(VERIFY(Expected, Expr),
	fun() ->
		AcTuAlReS = (catch (Expr)),
		case AcTuAlReS of
		    Expected -> ?LOG("Ok, ~p\n", [AcTuAlReS]);
		    _        ->	?ERROR(AcTuAlReS)
	       end,
		AcTuAlReS
	end()).

-define(IGNORE(Expr), 
	fun() ->
		AcTuAlReS = (catch (Expr)),
		?LOG("Ok, ~p\n", [AcTuAlReS]),
		AcTuAlReS
	end()).
