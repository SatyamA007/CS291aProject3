export const Compose = function(props) {
    const get = props.classref;
    return (
        <input id="message" onKeyUp={get.keyUpMessage} ref={elem => get.message = elem} type="text"/>

    );
}