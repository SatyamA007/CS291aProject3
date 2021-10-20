//CSS by Prof. Bryce Boe (CS291A UCSB) via https://chat.cs291.com/

import { Component } from "react";
import "./App.css";
import {LoginForm, start_stream} from "./components/LoginForm.jsx";
import {UserList} from "./components/UserList.jsx";
import {MessageList} from "./components/MessageList.jsx";
import {Compose} from "./components/Compose.jsx";

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
        start_stream();
    }
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
            start_stream();
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
                <MessageList classref={this}/>
                <div id="user_window">
                    <h2>Online</h2>
                    <UserList classref={this}/>
                </div>
            </div>
            <Compose classref={this}/>
        </section>
        <LoginForm classref={this}/>
    </div>
    );
  }
}

export default App;
