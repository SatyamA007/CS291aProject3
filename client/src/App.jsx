//CSS by Prof. Bryce Boe (CS291A UCSB) via https://chat.cs291.com/

import { Component } from "react";
import "./App.css";

let instance = null;
class App extends Component {
    
  constructor(props) {
    super(props);
    this.state = {
        updatedData: true
      };

      instance = this;
      this.keyUpLoginModal = this.keyUpLoginModal.bind(this);
      this.keyUpMessage = this.keyUpMessage.bind(this);      
  };

  messageToken=null;
  streamToken=null;
  stream = null;
  chats = [];
  users={};

    update_users() {
    this.setState(({updatedData})=>({['updatedData']:!updatedData}));
    }
    
    date_format(timestamp) {
        var date = new Date(timestamp * 1000);
        return date.toLocaleDateString("en-US") + " " + date.toLocaleTimeString("en-US");
    }
    
    output(chatText) {
        instance.chats.push(chatText);
        this.setState(({updatedData})=>({['updatedData']:!updatedData}));
        this.chat.scrollTop = this.chat.scrollHeight - this.chat.clientHeight;
    }

    chatMessages(){
        return this.chats.map(chatItem=>(
            <div>chatItem</div>
        )
        );
    }

    handle_connect() {
        this.message.disabled = false;
        this.message.value = "";
        this.title.classList.remove("disconnected");
    }
    handle_disconnect(clear_users) {
    this.message.disabled = true;
    this.message.value = "Please connect to send messages.";
    this.title.classList.add("disconnected");
    if (clear_users) {
        this.users = new Set();
        this.update_users();
        }
    }

    show_login() {
        this.url.value = sessionStorage.getItem("url") || "https://chat.cs291.com";
        this.login_modal.style.display = "block";
    }

  componentDidMount() {
    if (this.messageToken === null) {
        this.handle_disconnect(true);
        this.show_login();
    } else {
        this.start_stream();
    }
  }

  start_stream() {
    const instance2 = instance;
    this.stream = new EventSource(
        sessionStorage.getItem("url") + "/stream/" + this.streamToken
    );
    this.stream.addEventListener(
        "open",
        ()=> {
            instance2.handle_connect();
        }
    );
    this.stream.addEventListener(
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
    this.stream.addEventListener(
        "Join",
        (event)=> {
            var data = JSON.parse(event.data);
            instance2.users.add(data.user);
            instance2.update_users();
            instance2.output(instance2.date_format(data["created"]) + " JOIN: " + data.user);
        },
        false
    );
    this.stream.addEventListener(
        "Message",
        (event)=> {
            var data = JSON.parse(event.data);
            instance2.output(instance2.date_format(data["created"]) + " (" + data.user + ") " + data.message);
        },
        false
    );
    this.stream.addEventListener(
        "Part",
        (event)=> {
            var data = JSON.parse(event.data);
            instance2.users.delete(data.user);
            instance2.update_users();
            instance2.output(instance2.date_format(data["created"]) + " PART: " + data.user);
        },
        false
    );
    this.stream.addEventListener(
        "ServerStatus",
        (event) =>{
            var data = JSON.parse(event.data);
            instance2.output(instance2.date_format(data["created"]) + " STATUS: " + data.status);
        },
        false
    );
    this.stream.addEventListener(
        "Users",
        (event) =>{            
            const newArr = JSON.parse(event.data).users;
            instance2.users = new Set(newArr);
            instance2.update_users();
        },
        false
    );
    this.stream.addEventListener(
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

login() {
    var request = new XMLHttpRequest();
    var form = new FormData();
    form.append("password", this.password.value);
    form.append("username", this.username.value);
    sessionStorage.setItem("url", this.url.value);

    request.open("POST", sessionStorage.getItem("url") + "/login");
    request.onreadystatechange = function() {
        if (this.readyState !== 4) return;
        if (this.status === 201) {
            instance.login_modal.style.display = "none";
            instance.password.value = "";
            instance.username.value = "";
            const data = JSON.parse(this.responseText);
            instance.messageToken = data.message_token;
            instance.streamToken = data.stream_token;
            instance.start_stream();
        } else if (this.status === 403) {
            alert("Invalid username or password");
        } else if (this.status === 409) {
            alert(instance.username.value + " is already logged in");

        } else {
            alert(this.status + " failure to /login");
        }
    };
    request.send(form);
}

  keyUpLoginModal(event) {
    if (this.messageToken !== null || event.key !== 'Enter')
            return;
    this.login();
  }
  
  keyUpMessage(event) {
    if (this.messageToken === null || event.key !== 'Enter')
        return;
    event.preventDefault();
    if (this.message.value === "") return;
    var form = new FormData();
    form.append("message", this.message.value);

    var request = new XMLHttpRequest();
    request.open("POST", sessionStorage.getItem("url") + "/message");
    request.setRequestHeader(
        "Authorization",
        "Bearer " + this.messageToken
    );
    request.onreadystatechange = (event)=> {
        if (event.target.readyState === 4 && event.target.status !== 403 && this.messageToken != null) {
            this.messageToken = event.target.getResponseHeader("token");
        }
    }
    request.send(form);

    this.message.value = "";
  }



  render() {
    return (
      <div>
        <title>Budget-Cut Whatsapp</title>

        <section id="container">
            <h1 id="title" ref={elem => this.title = elem} class="disconnected">Budget-Cut Whatsapp</h1>
            <div id="window">
                <div id="chat" ref={elem => this.chat = elem}>
                    <ul>{(this.chats).map(item => (
                        <li>
                            {item} 
                        </li> 
                    ))}</ul>
                </div>
                <div id="user_window">
                    <h2>Online</h2>
                    <ul id="users" ref={elem => this.user_list = elem} >
                        {Array.from(this.users).sort().map(item => (
                        <li>
                            {item} 
                        </li> 
                    ))}
                    </ul>
                </div>
            </div>
            <input id="message" onKeyUp={this.keyUpMessage} ref={elem => this.message = elem} type="text"/>
        </section>
        <div id="login-modal" onKeyUp={this.keyUpLoginModal} ref={elem => this.login_modal = elem} >
        <div class="content">
            <h2>Login</h2>
            <div>
                <label>Chat URL <br /><input id="url" ref={elem => this.url = elem} type="text"/></label>
            </div>
            <div>
                <label>Username <br /><input id="username" ref={elem => this.username = elem} type="text"/></label>
            </div>
            <div>
                <label>Password <br /><input id="password" ref={elem => this.password = elem} type="password"/></label>
            </div>
        </div>
        </div>
    </div>
    );
  }
}
export default App;
