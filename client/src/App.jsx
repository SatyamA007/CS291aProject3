import { Component } from "react";
import "./App.css";

class App extends Component {
  constructor(props) {
    super(props);

    const server = new EventSource("http://localhost:3001/stream/a");
    server.addEventListener("message", (event) => {
      if (event.data === "Goodbye!") {
        console.log("Closing SSE connection");
        server.close();
      } else {
        console.log(event.data);
      }
    });
    server.onerror = (_event) => {
      console.log("Connection lost, reestablishing");
    };
  }

  render() {
    return (
      <div className="App">
        <header className="App-header">
          <p>
            Edit <code>src/App.jsx</code> and save to reload.
          </p>
          <a
            className="App-link"
            href="https://reactjs.org"
            target="_blank"
            rel="noopener noreferrer"
          >
            Learn React
          </a>
        </header>
      </div>
    );
  }
}
export default App;
