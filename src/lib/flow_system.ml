open Core.Std
open Flow_base


let discriminate_process_status s ret =
  begin match ret with
  | Lwt_unix.WEXITED 0 -> return ()
  | Lwt_unix.WEXITED n -> error (`system_command_error (s, `exited n))
  | Lwt_unix.WSIGNALED n -> error (`system_command_error (s, `signaled n))
  | Lwt_unix.WSTOPPED n -> error (`system_command_error (s, `stopped n))
  end

let system_command s =
  bind_on_error ~f:(fun e -> error (`system_command_error (s, `exn e)))
    (catch_io () ~f:Lwt_io.(fun () -> Lwt_unix.system s))
  >>= fun ret ->
  discriminate_process_status s ret

let sleep f =
  wrap_io Lwt_unix.sleep f


let get_system_command_output s =
  bind_on_error ~f:(fun e -> error (`system_command_error (s, `exn e)))
    (catch_io
       Lwt.(fun () ->
         let inprocess = Lwt_process.(open_process_full (shell s)) in
         Lwt_list.map_p Lwt_io.read
           [inprocess#stdout; inprocess#stderr; ]
         >>= fun output ->
         inprocess#status >>= fun status ->
         return (status, output))
       ())
  >>= fun (ret, output) ->
  discriminate_process_status s ret
  >>= fun () ->
  begin match output with
  | [out; err] -> return (out, err)
  | _ -> assert false
  end

let with_timeout time ~f =
  Lwt.catch
    begin fun () ->
      Lwt_unix.with_timeout time f
    end
    begin function
    | Lwt_unix.Timeout -> error (`timeout time)
    | e -> error (`io_exn e)
    end


let mkdir ?(perm=0o700) dirname =
  Lwt.catch
    Lwt.(fun () -> Lwt_unix.mkdir dirname perm >>= fun () -> return (Ok ()))
    begin function
    | Unix.Unix_error (Unix.EACCES, cmd, arg)  ->
      error (`system (`mkdir dirname, `wrong_access_rights perm))
    | Unix.Unix_error (Unix.EEXIST, cmd, arg)  ->
      error (`system (`mkdir dirname, `already_exists))
    | e ->
      error (`system (`mkdir dirname, `exn e))
    end

let mkdir_even_if_exists ?(perm=0o700) dirname =
  Lwt.catch
    Lwt.(fun () -> Lwt_unix.mkdir dirname perm >>= fun () -> return (Ok ()))
    begin function
    | Unix.Unix_error (Unix.EACCES, cmd, arg)  ->
      error (`system (`mkdir dirname, `wrong_access_rights perm))
    | Unix.Unix_error (Unix.EEXIST, cmd, arg)  -> return ()
    | e -> error (`system (`mkdir dirname, `exn e))
    end

let mkdir_p ?perm dirname =
  (* Code inspired by Core.Std.Unix *)
  let init, dirs =
    match Filename.parts dirname with
    | [] -> failwithf "Sys.mkdir_p: BUG! Filename.parts %s -> []" dirname ()
    | init :: dirs -> (init, dirs)
  in
  mkdir_even_if_exists ?perm init
  >>= fun () ->
  List.fold dirs ~init:(return init) ~f:(fun m part ->
    m >>= fun previous ->
    let dir = Filename.concat previous part in
    mkdir_even_if_exists ?perm dir
    >>= fun () ->
    return dir)
  >>= fun _ ->
  return ()

(*
  WARNING: this is a work-around for issue [329] with Lwt_unix.readlink.
  When it is fixed, we should go back to Lwt_unix.

  [329]: http://ocsigen.org/trac/ticket/329
*)
let lwt_unix_readlink l =
  let open Lwt in
  Lwt_preemptive.detach Unix.readlink l

let file_info ?(follow_symlink=false) path =
  let stat_fun =
    if follow_symlink then Lwt_unix.stat else Lwt_unix.lstat in
  (* eprintf "(l)stat %s? \n%!" path; *)
  Lwt.catch
    Lwt.(fun () -> stat_fun path >>= fun s -> return (Ok (`unix_stats s)))
    begin function
    | Unix.Unix_error (Unix.ENOENT, cmd, arg)  -> return `absent
    | e -> error (`system (`file_info path, `exn e))
    end
  >>= fun m ->
  let open Lwt_unix in
  begin match m with
  | `absent -> return `absent
  | `unix_stats stats ->
    begin match stats.st_kind with
    | S_DIR -> return (`directory)
    | S_REG -> return (`file (stats.st_size))
    | S_LNK ->
      (* eprintf "readlink %s? \n%!" path; *)
      begin
        Flow_base.catch_io lwt_unix_readlink path
        >>< begin function
        | Ok s -> return s
        | Error e -> error (`system (`file_info path, `exn e))
        end
      end
      >>= fun destination ->
      (* eprintf "readlink %s worked \n%!" path; *)
      return (`symlink destination)
    | S_CHR -> return (`character_device)
    | S_BLK -> return (`block_device)
    | S_FIFO -> return (`fifo)
    | S_SOCK -> return (`socket)
    end
  end

let remove path =
  let rec remove_aux path =
    file_info path
    >>= begin function
    | `absent -> return ()
    | `block_device
    | `character_device
    | `symlink _
    | `fifo
    | `socket
    | `file _-> wrap_io Lwt_unix.unlink path
    | `directory ->
      let f_stream = Lwt_unix.files_of_directory path in
      let next s =
        wrap_io ()
          ~f:Lwt.(fun () ->
            catch (fun () -> Lwt_stream.next s >>= fun n -> return (Some n))
              (function Lwt_stream.Empty -> return None
              | e -> fail e)
          ) in
      let rec loop stream =
        next stream
        >>= begin function
        | Some ".."
        | Some "." -> loop stream
        | Some name ->
          remove_aux (Filename.concat path name)
          >>= fun () ->
          loop stream
        | None -> return ()
        end
      in
      loop f_stream
      >>= fun () ->
      wrap_io Lwt_unix.rmdir path
    end
  in
  remove_aux path
  >>< begin function
  | Ok () -> return ()
  | Error (`io_exn e) -> error (`system (`remove path, `exn e))
  | Error (`system e) -> error (`system e)
  end

