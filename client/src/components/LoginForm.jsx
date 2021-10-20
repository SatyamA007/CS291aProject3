var get = null;
export const LoginForm = function(props) {
    get = props.classref;
    return (
        <div id="login-modal" onKeyUp={get.keyUpLoginModal} ref={elem => get.login_modal = elem} >
        <div class="content">
            <h2>Login</h2>
            <div>
                <label>Chat URL <br /><input id="url" ref={elem => get.url = elem} type="text"/></label>
            </div>
            <div>
                <label>Username <br /><input id="username" ref={elem => get.username = elem} type="text"/></label>
            </div>
            <div>
                <label>Password <br /><input id="password" ref={elem => get.password = elem} type="password"/></label>
            </div>
        </div>
        </div>
    );
}

export const start_stream = function() {
    const instance2 = get;
    get.stream = new EventSource(
        sessionStorage.getItem("url") + "/stream/" + get.streamToken
    );
    get.stream.addEventListener(
        "open",
        ()=> {
            instance2.handle_connect();
        }
    );
    get.stream.addEventListener(
        "Disconnect",
        ()=> {
            instance2.stream.close();//wrong, change!!
            instance2.handle_disconnect(true);
            instance2.messageToken = null;
            instance2.streamToken = null;
            instance2.chat.innerHTML = "";
            instance2.show_login();
        },
        false
    );
    get.stream.addEventListener(
        "Join",
        (event)=> {
            var data = JSON.parse(event.data);
            instance2.users.add(data.user);
            instance2.update_users();
            instance2.output(instance2.date_format(data["created"]) + " JOIN: " + data.user);
        },
        false
    );
    get.stream.addEventListener(
        "Message",
        (event)=> {
            var data = JSON.parse(event.data);
            instance2.output(instance2.date_format(data["created"]) + " (" + data.user + ") " + data.message);
        },
        false
    );
    get.stream.addEventListener(
        "Part",
        (event)=> {
            var data = JSON.parse(event.data);
            instance2.users.delete(data.user);
            instance2.update_users();
            instance2.output(instance2.date_format(data["created"]) + " PART: " + data.user);
        },
        false
    );
    get.stream.addEventListener(
        "ServerStatus",
        (event) =>{
            var data = JSON.parse(event.data);
            instance2.output(instance2.date_format(data["created"]) + " STATUS: " + data.status);
        },
        false
    );
    get.stream.addEventListener(
        "Users",
        (event) =>{            
            const newArr = JSON.parse(event.data).users;
            instance2.users = new Set(newArr);
            instance2.update_users();
        },
        false
    );
    get.stream.addEventListener(
        "error",
        (event) =>{
            if (event.target.readyState === 2) {
                instance2.messageToken = null;
                instance2.streamToken = null;
                instance2.handle_disconnect(true);
                instance2.show_login();
            } else {
                instance2.handle_disconnect(false);
                console.log("Disconnected, retrying");
            }
        },
        false
    );
}
