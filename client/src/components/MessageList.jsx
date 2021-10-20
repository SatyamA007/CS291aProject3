export const MessageList = function(props) {
    const get = props.classref;
    return (
        <div id="chat" ref={elem => get.chat = elem}>
                    <ul>{(get.chats).map(item => (
                        <li>
                            {item} 
                        </li> 
                    ))}</ul>
                </div>

    );
}